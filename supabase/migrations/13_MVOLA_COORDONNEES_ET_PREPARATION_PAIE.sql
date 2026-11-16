-- SMART AKADEMIA SCHOOL — Migration 13
-- Coordonnées MVola nominatives des enseignants, partenaires et promoteurs.
-- Vérification administrative du titulaire et préparation sécurisée des listes de paie.
-- Prérequis : migrations 01 à 10 et 12 appliquées.
-- La migration 11 est un diagnostic en lecture seule, pas une migration.
-- IMPORTANT : cette migration n'effectue aucun transfert MVola et ne stocke aucun secret API.

begin;

-- 1) Coordonnées MVola nominatives dans le profil (lecture autorisée uniquement au propriétaire et à l'admin).
alter table public.profiles
  add column if not exists mvola_number text,
  add column if not exists mvola_account_name text,
  add column if not exists mvola_owner_confirmed boolean not null default false,
  add column if not exists mvola_verified_at timestamptz,
  add column if not exists mvola_verified_by uuid references auth.users(id) on delete set null,
  add column if not exists mvola_verification_note text;

alter table public.profiles drop constraint if exists profiles_mvola_number_format_check;
alter table public.profiles add constraint profiles_mvola_number_format_check
  check (mvola_number is null or mvola_number ~ '^0(32|33|34|38|39)[0-9]{7}$');

-- 2) Instantané des coordonnées fournies au dépôt de candidature.
alter table public.role_applications
  add column if not exists mvola_number text,
  add column if not exists mvola_account_name text,
  add column if not exists mvola_owner_confirmed boolean not null default false,
  add column if not exists mvola_verified_at timestamptz,
  add column if not exists mvola_verified_by uuid references auth.users(id) on delete set null;

alter table public.role_applications drop constraint if exists role_applications_mvola_number_format_check;
alter table public.role_applications add constraint role_applications_mvola_number_format_check
  check (mvola_number is null or mvola_number ~ '^0(32|33|34|38|39)[0-9]{7}$');

-- Permet au candidat connecté d'enregistrer ses coordonnées dans son dossier.
grant insert(mvola_number,mvola_account_name,mvola_owner_confirmed) on public.role_applications to authenticated;

drop policy if exists role_applications_insert_applicant on public.role_applications;
create policy role_applications_insert_applicant on public.role_applications
  for insert to authenticated with check (
    user_id=auth.uid()
    and status='pending'
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='applicant' and p.requested_role=application_type)
    and (application_type <> 'partner' or monthly_commitment_accepted=true)
    and mvola_number is not null
    and nullif(trim(mvola_account_name),'') is not null
    and mvola_owner_confirmed=true
  );

-- 3) Normalisation et enregistrement : aucune mise à jour directe du rôle ou de la vérification par le navigateur.
create or replace function public.save_akademia_mvola_profile(
  p_mvola_number text,
  p_mvola_account_name text,
  p_owner_confirmed boolean
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  caller uuid := auth.uid();
  p public.profiles%rowtype;
  digits text;
  normalized text;
  normalized_name text;
  details_changed boolean;
begin
  if caller is null then raise exception 'Connexion requise.'; end if;
  select * into p from public.profiles where id=caller for update;
  if not found then raise exception 'Profil introuvable.'; end if;
  if not (
    p.role in ('teacher','partner','promoter')
    or (p.role='applicant' and p.requested_role in ('teacher','partner','promoter'))
  ) then
    raise exception 'Les coordonnées MVola nominatives sont réservées aux enseignants, partenaires et promoteurs.';
  end if;

  digits := regexp_replace(coalesce(p_mvola_number,''), '[^0-9]', '', 'g');
  if left(digits,3)='261' then
    normalized := '0' || substr(digits,4);
  elsif digits ~ '^(32|33|34|38|39)[0-9]{7}$' then
    normalized := '0' || digits;
  else
    normalized := digits;
  end if;
  if normalized !~ '^0(32|33|34|38|39)[0-9]{7}$' then
    raise exception 'Numéro MVola invalide. Utilisez le format 034XXXXXXX ou +26134XXXXXXX.';
  end if;

  normalized_name := trim(coalesce(p_mvola_account_name,''));
  if length(normalized_name) < 3 then
    raise exception 'Le nom exact du titulaire MVola est obligatoire.';
  end if;
  if p_owner_confirmed is distinct from true then
    raise exception 'Vous devez certifier que le compte MVola est enregistré à votre nom.';
  end if;

  details_changed :=
    p.mvola_number is distinct from normalized
    or p.mvola_account_name is distinct from normalized_name
    or p.mvola_owner_confirmed is distinct from true;

  update public.profiles
    set mvola_number=normalized,
        mvola_account_name=normalized_name,
        mvola_owner_confirmed=true,
        mvola_verified_at=case when details_changed then null else mvola_verified_at end,
        mvola_verified_by=case when details_changed then null else mvola_verified_by end,
        mvola_verification_note=case when details_changed then null else mvola_verification_note end
  where id=caller;

  update public.role_applications
    set mvola_number=normalized,
        mvola_account_name=normalized_name,
        mvola_owner_confirmed=true,
        mvola_verified_at=case
          when mvola_number is distinct from normalized
            or mvola_account_name is distinct from normalized_name
            or mvola_owner_confirmed is distinct from true
          then null else mvola_verified_at end,
        mvola_verified_by=case
          when mvola_number is distinct from normalized
            or mvola_account_name is distinct from normalized_name
            or mvola_owner_confirmed is distinct from true
          then null else mvola_verified_by end
  where user_id=caller and status='pending';

  return jsonb_build_object(
    'saved',true,
    'mvola_number',normalized,
    'mvola_account_name',normalized_name,
    'verification_status',case when details_changed then 'pending_admin_review'
      when p.mvola_verified_at is not null then 'verified' else 'pending_admin_review' end
  );
end;
$$;
revoke all on function public.save_akademia_mvola_profile(text,text,boolean) from public,anon;
grant execute on function public.save_akademia_mvola_profile(text,text,boolean) to authenticated;

-- 4) Validation administrative explicite après comparaison avec les pièces/justificatifs du titulaire.
create or replace function public.admin_verify_akademia_mvola_profile(
  p_user_id uuid,
  p_verified boolean,
  p_note text default null
) returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare p public.profiles%rowtype;
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administration.'; end if;
  select * into p from public.profiles where id=p_user_id for update;
  if not found then raise exception 'Profil destinataire introuvable.'; end if;
  if p.role not in ('applicant','teacher','partner','promoter') then
    raise exception 'Ce profil n’est pas un bénéficiaire professionnel.';
  end if;

  if p_verified then
    if p.mvola_number is null or p.mvola_number !~ '^0(32|33|34|38|39)[0-9]{7}$'
       or nullif(trim(p.mvola_account_name),'') is null
       or p.mvola_owner_confirmed is distinct from true then
      raise exception 'Le numéro, le nom du titulaire et la déclaration du candidat doivent être complets.';
    end if;
    update public.profiles set mvola_verified_at=now(),mvola_verified_by=auth.uid(),
      mvola_verification_note=nullif(trim(p_note),'') where id=p_user_id;
    update public.role_applications set mvola_verified_at=now(),mvola_verified_by=auth.uid()
      where user_id=p_user_id and status='pending';
  else
    update public.profiles set mvola_verified_at=null,mvola_verified_by=null,
      mvola_verification_note=nullif(trim(p_note),'') where id=p_user_id;
    update public.role_applications set mvola_verified_at=null,mvola_verified_by=null
      where user_id=p_user_id and status='pending';
  end if;
  return true;
end;
$$;
revoke all on function public.admin_verify_akademia_mvola_profile(uuid,boolean,text) from public,anon;
grant execute on function public.admin_verify_akademia_mvola_profile(uuid,boolean,text) to authenticated;

-- 5) Remplace la validation candidature existante pour exiger la vérification du MVola avant approbation.
create or replace function public.admin_review_role_application(
  p_application_id uuid, p_decision text, p_review_note text default null
) returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  app public.role_applications%rowtype;
  code text;
  partner_payment jsonb;
  partner_proof_path text;
  partner_payment_method text;
  partner_transaction_reference text;
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Décision invalide.'; end if;

  select * into app
  from public.role_applications
  where id=p_application_id
  for update;
  if not found or app.status<>'pending' then
    raise exception 'Candidature introuvable ou déjà traitée.';
  end if;

  -- Toute candidature professionnelle doit disposer d'un compte MVola nominatif
  -- dont le titulaire a été vérifié manuellement par l'administration.
  if p_decision='approved' and not exists(
    select 1 from public.profiles p
    where p.id=app.user_id
      and p.mvola_verified_at is not null
      and p.mvola_owner_confirmed=true
      and p.mvola_number=app.mvola_number
      and p.mvola_account_name=app.mvola_account_name
  ) then
    raise exception 'Le titulaire du compte MVola doit être vérifié par l’administration avant l’approbation.';
  end if;

  if p_decision='approved' and app.application_type in ('teacher','promoter') then
    if jsonb_typeof(app.documents)<>'array'
      or not exists(
        select 1 from jsonb_array_elements(app.documents) d
        where d->>'kind'='identity_photo'
          and exists(select 1 from storage.objects o
            where o.bucket_id='role-application-documents'
              and o.name=d->>'path' and o.name like app.user_id::text||'/%')
      )
      or not exists(
        select 1 from jsonb_array_elements(app.documents) d
        where d->>'kind'='diploma_proof'
          and exists(select 1 from storage.objects o
            where o.bucket_id='role-application-documents'
              and o.name=d->>'path' and o.name like app.user_id::text||'/%')
      ) then
      raise exception 'La photo d’identité et la preuve du diplôme doivent être téléversées dans le stockage privé.';
    end if;
  end if;

  if p_decision='approved' and app.application_type='teacher'
     and nullif(trim(app.specialty),'') is null then
    raise exception 'La spécialité proposée doit être renseignée.';
  end if;

  if p_decision='approved' and app.application_type='promoter'
     and app.diploma_level not in ('Baccalauréat','Bac+2','Licence','Master','Doctorat') then
    raise exception 'Le niveau de diplôme doit être au minimum le Baccalauréat.';
  end if;

  -- Préserve les contrôles introduits en migration 10 :
  -- l'approbation partenaire crée une cotisation EN ATTENTE, jamais un paiement validé.
  if p_decision='approved' and app.application_type='partner' then
    if nullif(trim(app.organization_name),'') is null then
      raise exception 'Le nom du partenaire ou de l’organisme est obligatoire.';
    end if;
    if app.monthly_commitment_accepted is distinct from true then
      raise exception 'L’engagement de cotisation mensuelle doit être accepté.';
    end if;
    if jsonb_typeof(app.documents)<>'array' then
      raise exception 'La preuve de cotisation partenaire est obligatoire.';
    end if;

    select d into partner_payment
    from jsonb_array_elements(app.documents) d
    where d->>'kind'='payment_proof'
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
    if length(partner_transaction_reference)<3
       or partner_payment->>'payment_reference'<>'FINANCEMENT'
       or coalesce((partner_payment->>'amount_ar')::integer,0)<>100000 then
      raise exception 'La transaction partenaire doit porter le montant 100 000 Ar et la référence FINANCEMENT.';
    end if;
    if not exists(
      select 1 from storage.objects o
      where o.bucket_id='partner-payment-proofs'
        and o.name=partner_proof_path
        and o.name like app.user_id::text||'/%'
    ) then
      raise exception 'La preuve de paiement partenaire est introuvable dans le stockage privé.';
    end if;
  end if;

  update public.role_applications
    set status=p_decision,
        review_note=nullif(trim(p_review_note),''),
        reviewed_by=auth.uid(),
        reviewed_at=now()
  where id=p_application_id and status='pending';
  if not found then raise exception 'La candidature a déjà été traitée.'; end if;

  if p_decision='approved' then
    if app.application_type='promoter' then
      loop
        code := upper(substr(encode(gen_random_bytes(8),'hex'),1,8));
        exit when not exists(select 1 from public.profiles where referral_code=code);
      end loop;
    else
      code := null;
    end if;

    update public.profiles
      set role=app.application_type,
          registration_status='approved',
          referral_code=case when app.application_type='promoter' then code else referral_code end
    where id=app.user_id and role='applicant';
    if not found then
      raise exception 'Profil candidat introuvable ou déjà converti.';
    end if;

    if app.application_type='partner' then
      insert into public.partner_contributions(
        user_id,amount_ar,payment_method,payment_reference,
        transaction_reference,proof_path,status
      ) values(
        app.user_id,100000,partner_payment_method,'FINANCEMENT',
        partner_transaction_reference,partner_proof_path,'pending'
      );
    end if;
  end if;

  return coalesce(code,'');
end;
$$;
revoke all on function public.admin_review_role_application(uuid,text,text) from public,anon;
grant execute on function public.admin_review_role_application(uuid,text,text) to authenticated;

-- 6) RPC de lecture paie : uniquement demandes en attente de salaires/avances enseignants
-- et commissions promoteurs. Le numéro MVola n'est exposé qu'à l'administrateur.
create or replace function public.list_akademia_payroll_queue()
returns table(
  request_id uuid,
  user_id uuid,
  full_name text,
  email text,
  role text,
  request_type text,
  amount_ar integer,
  created_at timestamptz,
  mvola_number text,
  mvola_account_name text,
  mvola_owner_confirmed boolean,
  mvola_verified_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Accès à la liste de paie réservé à l’administration.'; end if;
  return query
    select fr.id,fr.user_id,p.full_name,p.email,p.role,fr.request_type,fr.amount_ar,fr.created_at,
      p.mvola_number,p.mvola_account_name,p.mvola_owner_confirmed,p.mvola_verified_at
    from public.finance_requests fr
    join public.profiles p on p.id=fr.user_id
    where fr.status='pending'
      and fr.request_type in ('teacher_salary','teacher_advance','promoter_payout')
      and p.role in ('teacher','promoter')
    order by fr.created_at asc;
end;
$$;
revoke all on function public.list_akademia_payroll_queue() from public,anon;
grant execute on function public.list_akademia_payroll_queue() to authenticated;

-- 7) Sécurise la clôture de paie : un paiement ne peut être marqué payé qu'après
-- vérification administrative du compte MVola du bénéficiaire et saisie de la référence réelle.
create or replace function public.admin_review_finance_request(
  p_request_id uuid,
  p_decision text,
  p_transfer_reference text default null,
  p_review_note text default null
) returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  req public.finance_requests%rowtype;
  beneficiary public.profiles%rowtype;
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administration.'; end if;
  if p_decision is null or p_decision not in ('approved','rejected') then
    raise exception 'Décision invalide.';
  end if;

  select * into req from public.finance_requests
    where id=p_request_id and status='pending' for update;
  if not found then raise exception 'Demande introuvable ou déjà traitée.'; end if;

  if p_decision='approved' then
    if nullif(trim(p_transfer_reference),'') is null then
      raise exception 'Renseignez la référence du virement réellement effectué.';
    end if;
    select * into beneficiary from public.profiles where id=req.user_id;
    if not found then raise exception 'Profil du bénéficiaire introuvable.'; end if;
    if not (
      (req.request_type in ('teacher_salary','teacher_advance') and beneficiary.role='teacher')
      or (req.request_type='promoter_payout' and beneficiary.role='promoter')
    ) then
      raise exception 'Le type de demande ne correspond pas au rôle du bénéficiaire.';
    end if;
    if beneficiary.mvola_verified_at is null
       or beneficiary.mvola_owner_confirmed is distinct from true
       or beneficiary.mvola_number is null
       or beneficiary.mvola_number !~ '^0(32|33|34|38|39)[0-9]{7}$'
       or nullif(trim(beneficiary.mvola_account_name),'') is null then
      raise exception 'Paiement bloqué : le compte MVola du bénéficiaire doit être complet et vérifié.';
    end if;
  end if;

  update public.finance_requests
    set status=p_decision,
        transfer_reference=case when p_decision='approved' then trim(p_transfer_reference) else null end,
        review_note=nullif(trim(p_review_note),''),
        reviewed_by=auth.uid(), reviewed_at=now()
    where id=p_request_id and status='pending';
  if not found then raise exception 'Demande déjà traitée.'; end if;
  return true;
end;
$$;
revoke all on function public.admin_review_finance_request(uuid,text,text,text) from public,anon;
grant execute on function public.admin_review_finance_request(uuid,text,text,text) to authenticated;

-- 8) Liste restreinte des comptes MVola de l'équipe : seuls les administrateurs peuvent la lire.
create or replace function public.list_akademia_mvola_profiles()
returns table(
  user_id uuid,
  full_name text,
  email text,
  role text,
  mvola_number text,
  mvola_account_name text,
  mvola_owner_confirmed boolean,
  mvola_verified_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Liste des comptes MVola réservée à l’administration.'; end if;
  return query
    select p.id,p.full_name,p.email,p.role,p.mvola_number,p.mvola_account_name,p.mvola_owner_confirmed,p.mvola_verified_at
    from public.profiles p
    where p.role in ('teacher','partner','promoter')
      and p.registration_status='approved'
    order by p.role,p.full_name;
end;
$$;
revoke all on function public.list_akademia_mvola_profiles() from public,anon;
grant execute on function public.list_akademia_mvola_profiles() to authenticated;

commit;
