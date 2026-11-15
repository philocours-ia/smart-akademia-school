-- Smart Akademia School — Migration 14
-- Paiements marchands MVola vérifiés côté serveur pour les abonnements mensuels élèves.
-- Prérequis : migrations 01 à 08 appliquées. Sauvegarder et tester avant production.
-- Les secrets MVola ne sont jamais stockés dans PostgreSQL ni dans le frontend.

begin;

create table if not exists public.mvola_payment_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key uuid not null,
  plan_code text not null check (plan_code = 'monthly'),
  amount_ar integer not null check (amount_ar = 15000),
  currency text not null default 'Ar' check (currency = 'Ar'),
  payer_msisdn text not null check (payer_msisdn ~ '^0(32|33|34|38|39)[0-9]{7}$'),
  external_reference text not null unique,
  server_correlation_id text,
  financial_transaction_id text,
  status text not null default 'created'
    check (status in ('created','pending','paid','failed','cancelled')),
  provider_status text,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmed_at timestamptz,
  unique (user_id, idempotency_key)
);

create index if not exists mvola_payment_orders_user_created_idx
  on public.mvola_payment_orders(user_id, created_at desc);
create unique index if not exists mvola_payment_orders_correlation_unique
  on public.mvola_payment_orders(server_correlation_id)
  where server_correlation_id is not null;
create unique index if not exists mvola_payment_orders_financial_id_unique
  on public.mvola_payment_orders(financial_transaction_id)
  where financial_transaction_id is not null;

alter table public.mvola_payment_orders enable row level security;
revoke all on public.mvola_payment_orders from public, anon, authenticated;
grant select on public.mvola_payment_orders to authenticated;
drop policy if exists mvola_payment_orders_select_own on public.mvola_payment_orders;
create policy mvola_payment_orders_select_own on public.mvola_payment_orders
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

comment on table public.mvola_payment_orders is
  'MVola Merchant Pay requests. Only the server-side Edge Function writes or confirms rows.';
comment on column public.mvola_payment_orders.payer_msisdn is
  'Normalized Madagascar payer phone number; visible only to the owner and administrators.';

-- Atomically records a verified MVola success and creates the monthly subscription.
-- Callable only with the Supabase service-role JWT from the trusted Edge Function.
create or replace function public.settle_akademia_mvola_subscription(
  p_payment_id uuid,
  p_financial_transaction_id text,
  p_confirmed_amount integer,
  p_confirmed_currency text,
  p_external_reference text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  payment public.mvola_payment_orders%rowtype;
  student public.profiles%rowtype;
  new_subscription_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Settlement MVola réservé au service de paiement.';
  end if;
  if nullif(trim(p_financial_transaction_id), '') is null then
    raise exception 'Référence financière MVola manquante.';
  end if;

  select * into payment from public.mvola_payment_orders
    where id = p_payment_id for update;
  if not found then raise exception 'Demande de paiement introuvable.'; end if;
  if payment.status = 'paid' then
    if payment.financial_transaction_id = p_financial_transaction_id then
      return payment.subscription_id;
    end if;
    raise exception 'Cette demande a déjà été réglée avec une autre transaction.';
  end if;
  if payment.status not in ('created','pending') then
    raise exception 'Cette demande de paiement n’est plus réglable.';
  end if;
  if payment.amount_ar <> p_confirmed_amount
     or payment.currency <> p_confirmed_currency
     or payment.external_reference <> p_external_reference then
    raise exception 'Le montant, la devise ou la référence MVola ne correspond pas à la demande.';
  end if;

  select * into student from public.profiles where id = payment.user_id for update;
  if not found or student.role <> 'student' or student.registration_status <> 'approved' then
    raise exception 'Seul un élève approuvé peut recevoir un abonnement.';
  end if;

  -- Les abonnements mensuels sont activés automatiquement après confirmation MVola.
  -- Le marqueur de preuve n'est pas un reçu utilisateur : la confirmation provider est
  -- enregistrée dans mvola_payment_orders et l'activation n'utilise pas le RPC manuel.
  insert into public.subscriptions (
    user_id, full_name, series, phone, payment_method, reference_code,
    transaction_reference, proof_path, proof_name, status, plan_code, amount_ar
  ) values (
    payment.user_id, student.full_name, student.series, payment.payer_msisdn,
    'MVola', 'AKADEMIA', p_financial_transaction_id,
    'mvola-confirmed://' || payment.id::text, 'Confirmation API MVola',
    'actif', 'monthly', 15000
  ) returning id into new_subscription_id;

  update public.mvola_payment_orders
    set status = 'paid',
        financial_transaction_id = p_financial_transaction_id,
        provider_status = 'SUCCESSFUL',
        subscription_id = new_subscription_id,
        confirmed_at = now(), updated_at = now()
    where id = payment.id;

  return new_subscription_id;
end;
$$;

revoke all on function public.settle_akademia_mvola_subscription(uuid,text,integer,text,text) from public, anon, authenticated;
grant execute on function public.settle_akademia_mvola_subscription(uuid,text,integer,text,text) to service_role;

commit;
