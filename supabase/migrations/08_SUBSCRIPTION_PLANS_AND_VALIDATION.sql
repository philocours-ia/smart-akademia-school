-- SMART AKADEMIA SCHOOL — Migration 08
-- Abonnement mensuel 15 000 Ar / 30 jours et annuel 145 000 Ar / fin d'année scolaire.
-- Prérequis : migrations 01 à 07 exécutées. Pour les dossiers anciens, l'ancien tarif
-- de 5 000 Ar est conservé uniquement à titre historique (plan_code='legacy').
-- La date de fin annuelle doit être renseignée par l'administrateur selon le calendrier officiel.

begin;

alter table public.subscriptions add column if not exists plan_code text;
alter table public.subscriptions add column if not exists amount_ar integer;
alter table public.subscriptions add column if not exists annual_valid_until date;
update public.subscriptions set plan_code='legacy',amount_ar=5000
  where plan_code is null or amount_ar is null;
alter table public.subscriptions alter column plan_code set default 'monthly';
alter table public.subscriptions alter column plan_code set not null;
alter table public.subscriptions alter column amount_ar set default 15000;
alter table public.subscriptions alter column amount_ar set not null;
alter table public.subscriptions drop constraint if exists subscriptions_plan_amount_check;
alter table public.subscriptions add constraint subscriptions_plan_amount_check check (
  (plan_code='monthly' and amount_ar=15000 and annual_valid_until is null)
  or (plan_code='annual' and amount_ar=145000)
  or (plan_code='legacy' and amount_ar=5000)
);

-- Les nouvelles demandes doivent porter un tarif exact, un reçu et un transaction ID.
drop policy if exists subscriptions_insert_own_pending on public.subscriptions;
create policy subscriptions_insert_own_pending on public.subscriptions for insert to authenticated
with check(
  user_id=auth.uid() and reference_code='AKADEMIA' and status='en_attente'
  and transaction_reference is not null and length(trim(transaction_reference))>=3
  and split_part(proof_path,'/',1)=auth.uid()::text
  and ((plan_code='monthly' and amount_ar=15000) or (plan_code='annual' and amount_ar=145000))
  and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='student'
    and p.registration_status='approved' and p.series=subscriptions.series)
);
grant insert(plan_code,amount_ar) on public.subscriptions to authenticated;

-- Empêche de modifier les champs de décision depuis le navigateur : seule la RPC admin tranche.
revoke update(status,activated_at,expires_at) on public.subscriptions from authenticated;

create or replace function public.issue_akademia_access_ticket()
returns trigger language plpgsql security definer set search_path=public
as $$
declare current_expiry timestamptz;
begin
  if new.status='actif' and new.access_ticket is null then
    if new.plan_code='annual' then
      if new.annual_valid_until is null or new.annual_valid_until<current_date then
        raise exception 'La date de fin annuelle doit être renseignée et valide.';
      end if;
      new.expires_at := ((new.annual_valid_until + 1)::timestamp at time zone current_setting('TimeZone'));
    else
      select max(s.expires_at) into current_expiry from public.subscriptions s
        where s.user_id=new.user_id and s.id<>new.id and s.status='actif' and s.expires_at>now();
      new.expires_at := greatest(now(),coalesce(current_expiry,now()))+interval '30 days';
    end if;
    new.access_ticket := 'AKD-'||to_char(clock_timestamp(),'YYMMDD')||'-'||upper(encode(gen_random_bytes(5),'hex'));
    new.activated_at := coalesce(new.activated_at,now());
  end if;
  return new;
end; $$;
revoke all on function public.issue_akademia_access_ticket() from public;
drop trigger if exists subscriptions_issue_ticket on public.subscriptions;
create trigger subscriptions_issue_ticket before insert or update of status on public.subscriptions
for each row execute function public.issue_akademia_access_ticket();

create or replace function public.admin_activate_student_subscription(p_subscription_id uuid,p_annual_valid_until date default null)
returns text language plpgsql security definer set search_path=public
as $$
declare s public.subscriptions%rowtype;
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  select * into s from public.subscriptions where id=p_subscription_id for update;
  if not found or s.status<>'en_attente' then raise exception 'Demande introuvable ou déjà traitée.'; end if;
  if s.plan_code='annual' and (p_annual_valid_until is null or p_annual_valid_until<current_date) then
    raise exception 'Renseignez la date réelle de fin de l’année scolaire avant de valider.';
  end if;
  if s.plan_code<>'annual' and p_annual_valid_until is not null then
    raise exception 'Une date annuelle ne doit être fournie que pour le plan annuel.';
  end if;
  if s.reference_code<>'AKADEMIA' or s.transaction_reference is null or length(trim(s.transaction_reference))<3 then
    raise exception 'Référence ou identifiant de transaction manquant.';
  end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='payment-proofs' and o.name=s.proof_path) then
    raise exception 'Preuve de paiement introuvable dans le stockage privé.';
  end if;
  update public.subscriptions set annual_valid_until=p_annual_valid_until,status='actif'
    where id=p_subscription_id;
  select access_ticket into s.access_ticket from public.subscriptions where id=p_subscription_id;
  return s.access_ticket;
end; $$;
revoke all on function public.admin_activate_student_subscription(uuid,date) from public;
grant execute on function public.admin_activate_student_subscription(uuid,date) to authenticated;

create or replace function public.admin_reject_student_subscription(p_subscription_id uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  update public.subscriptions set status='refuse'
    where id=p_subscription_id and status='en_attente';
  if not found then raise exception 'Demande introuvable ou déjà traitée.'; end if;
  return true;
end; $$;
revoke all on function public.admin_reject_student_subscription(uuid,text) from public;
grant execute on function public.admin_reject_student_subscription(uuid,text) to authenticated;

commit;

-- Contrôle rapide (lecture seule).
select plan_code,amount_ar,status,count(*) as demandes from public.subscriptions group by plan_code,amount_ar,status order by plan_code,status;
