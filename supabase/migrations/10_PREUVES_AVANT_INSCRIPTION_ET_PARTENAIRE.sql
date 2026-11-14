-- SMART AKADEMIA SCHOOL — Migration 10
-- Renforce le parcours d'inscription : justificatifs demandés avant la création du compte
-- dans l'interface, transfert vers les buckets privés après authentification, et
-- enregistrement automatique de la première cotisation partenaire après approbation.
-- Prérequis : migrations 01 à 09 déjà appliquées.
-- Exécuter une seule fois dans Supabase SQL Editor après sauvegarde.
-- Aucun mot de passe, clé service_role ou secret ne figure dans ce fichier.

begin;

-- Un candidat partenaire peut déposer sa première preuve avant que l'administrateur
-- ne transforme son profil applicant en partner. Le compte reste limité pendant l'examen.
drop policy if exists partner_proofs_insert_own on storage.objects;
create policy partner_proofs_insert_own
on storage.objects for insert to authenticated
with check (
  bucket_id = 'partner-payment-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (p.role = 'partner' or (p.role = 'applicant' and p.requested_role = 'partner'))
  )
);

drop policy if exists partner_proofs_insert_guard on storage.objects;
create policy partner_proofs_insert_guard
on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id <> 'partner-payment-proofs'
  or (
    (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (p.role = 'partner' or (p.role = 'applicant' and p.requested_role = 'partner'))
    )
  )
);

-- L'approbation d'une candidature partenaire exige désormais sa preuve de versement
-- déposée avant le dépôt de candidature, puis crée une cotisation en attente.
-- La validation de cette cotisation reste une décision manuelle distincte qui génère
-- le ticket partenaire via admin_decide_partner_contribution().
create or replace function public.admin_review_role_application(
  p_application_id uuid,
  p_decision text,
  p_review_note text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  app public.role_applications%rowtype;
  code text;
  partner_payment jsonb;
  partner_proof_path text;
  partner_payment_method text;
  partner_transaction_reference text;
begin
  if not public.is_admin() then
    raise exception 'Action réservée à l’administrateur.';
  end if;
  if p_decision not in ('approved','rejected') then
    raise exception 'Décision invalide.';
  end if;

  select * into app
  from public.role_applications
  where id = p_application_id
  for update;

  if not found or app.status <> 'pending' then
    raise exception 'Candidature introuvable ou déjà traitée.';
  end if;

  if p_decision = 'approved' and app.application_type in ('teacher','promoter') then
    if jsonb_typeof(app.documents) <> 'array' or jsonb_array_length(app.documents) < 2
      or not exists (
        select 1 from jsonb_array_elements(app.documents) d
        where d->>'kind' = 'identity_photo'
          and exists (
            select 1 from storage.objects o
            where o.bucket_id = 'role-application-documents'
              and o.name = d->>'path'
              and o.name like app.user_id::text || '/%'
          )
      )
      or not exists (
        select 1 from jsonb_array_elements(app.documents) d
        where d->>'kind' = 'diploma_proof'
          and exists (
            select 1 from storage.objects o
            where o.bucket_id = 'role-application-documents'
              and o.name = d->>'path'
              and o.name like app.user_id::text || '/%'
          )
      ) then
      raise exception 'La photo d’identité et la preuve du diplôme doivent être téléversées dans le stockage privé.';
    end if;
  end if;

  if p_decision = 'approved' and app.application_type = 'teacher'
    and nullif(trim(app.specialty),'') is null then
    raise exception 'La spécialité proposée doit être renseignée.';
  end if;

  if p_decision = 'approved' and app.application_type = 'promoter'
    and app.diploma_level not in ('Baccalauréat','Bac+2','Licence','Master','Doctorat') then
    raise exception 'Le niveau de diplôme doit être au minimum le Baccalauréat.';
  end if;

  if p_decision = 'approved' and app.application_type = 'partner' then
    if nullif(trim(app.organization_name),'') is null then
      raise exception 'Le nom du partenaire ou de l’organisme est obligatoire.';
    end if;
    if not app.monthly_commitment_accepted then
      raise exception 'L’engagement de cotisation mensuelle doit être accepté.';
    end if;
    if jsonb_typeof(app.documents) <> 'array' then
      raise exception 'La preuve de cotisation partenaire est obligatoire.';
    end if;
    select d into partner_payment
    from jsonb_array_elements(app.documents) d
    where d->>'kind' = 'payment_proof'
    limit 1;
    if partner_payment is null then
      raise exception 'La preuve de la première cotisation de 100 000 Ar doit être jointe avant la candidature.';
    end if;

    partner_proof_path := partner_payment->>'path';
    partner_payment_method := partner_payment->>'payment_method';
    partner_transaction_reference := trim(coalesce(partner_payment->>'transaction_reference',''));

    if coalesce(partner_payment_method,'') not in ('MVola','Binance Pay') then
      raise exception 'Le mode de paiement partenaire doit être MVola ou Binance Pay.';
    end if;
    if length(partner_transaction_reference) < 3
      or partner_payment->>'payment_reference' <> 'FINANCEMENT'
      or coalesce((partner_payment->>'amount_ar')::integer,0) <> 100000 then
      raise exception 'La transaction partenaire doit porter le montant 100 000 Ar et la référence FINANCEMENT.';
    end if;
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'partner-payment-proofs'
        and o.name = partner_proof_path
        and o.name like app.user_id::text || '/%'
    ) then
      raise exception 'La preuve de paiement partenaire est introuvable dans le stockage privé.';
    end if;
  end if;

  update public.role_applications
  set status = p_decision,
      review_note = nullif(trim(p_review_note),''),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_application_id;

  if p_decision = 'approved' then
    if app.application_type = 'promoter' then
      loop
        code := upper(substr(encode(gen_random_bytes(8),'hex'),1,8));
        exit when not exists(select 1 from public.profiles where referral_code = code);
      end loop;
    else
      code := null;
    end if;

    update public.profiles
    set role = app.application_type,
        registration_status = 'approved',
        referral_code = case when app.application_type = 'promoter' then code else referral_code end
    where id = app.user_id and role = 'applicant';
    if not found then
      raise exception 'Profil candidat introuvable ou déjà converti.';
    end if;

    if app.application_type = 'partner' then
      insert into public.partner_contributions(
        user_id, amount_ar, payment_method, payment_reference,
        transaction_reference, proof_path, status
      ) values (
        app.user_id, 100000, partner_payment_method, 'FINANCEMENT',
        partner_transaction_reference, partner_proof_path, 'pending'
      );
    end if;
  end if;

  return coalesce(code,'');
end;
$$;

revoke all on function public.admin_review_role_application(uuid,text,text) from public;
grant execute on function public.admin_review_role_application(uuid,text,text) to authenticated;

commit;

-- Diagnostic en lecture seule : état du compte administrateur autorisé.
select
  a.email as email_autorise,
  u.id as auth_user_id,
  u.email_confirmed_at,
  p.role as profil_role,
  p.registration_status,
  p.must_change_password,
  case
    when u.id is null then 'AUTH_USER_ABSENT : créer ou retrouver l’utilisateur dans Authentication > Users'
    when u.email_confirmed_at is null then 'EMAIL_NON_CONFIRME : confirmer l’adresse dans Supabase Auth'
    when p.id is null then 'PROFIL_ABSENT : le déclencheur Auth ou le profil doit être réparé'
    when p.role <> 'admin' then 'ROLE_INCORRECT : vérifier l’allowlist et le profil avec le propriétaire'
    when p.must_change_password then 'PREMIERE_CONNEXION : changer le mot de passe après connexion'
    else 'COMPTE_ADMIN_CONFIGURE'
  end as diagnostic
from public.akademia_admin_allowlist a
left join auth.users u on lower(trim(u.email)) = a.email
left join public.profiles p on p.id = u.id
where a.enabled = true
order by a.email;
