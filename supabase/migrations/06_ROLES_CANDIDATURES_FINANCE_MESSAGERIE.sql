-- SMART AKADEMIA SCHOOL — Migration 06
-- Candidatures enseignants/partenaires/promoteurs, affectations, paiements partenaires,
-- commissions promoteurs, paie/avances enseignants, demandes internes, ressources et messages.
-- Prérequis : scripts 01, 02, 03 et 05 déjà appliqués.
-- Exécuter une seule fois dans Supabase SQL Editor, après sauvegarde.
-- Aucun mot de passe, service_role ou secret n'est stocké dans ce fichier.

begin;

-- 1) Élargissement des rôles et prise en charge des comptes candidats.
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.profiles'::regclass and contype = 'c'
      and (pg_get_constraintdef(oid) ilike '%role%' or pg_get_constraintdef(oid) ilike '%series%')
  loop
    execute format('alter table public.profiles drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('student','admin','applicant','teacher','partner','promoter')),
  add constraint profiles_series_check
  check (series in ('Seconde','Première','Première L','Première S','Première OSE','Terminale L','Terminale S','Terminale OSE','Administrateur','Candidat'));

alter table public.profiles
  add column if not exists requested_role text,
  add column if not exists referral_code text,
  add column if not exists referred_by uuid references public.profiles(id) on delete set null;

alter table public.profiles drop constraint if exists profiles_requested_role_check;
alter table public.profiles add constraint profiles_requested_role_check
  check (requested_role is null or requested_role in ('teacher','partner','promoter'));
create unique index if not exists profiles_referral_code_unique
  on public.profiles(referral_code) where referral_code is not null;
create index if not exists profiles_referred_by_idx on public.profiles(referred_by);

-- Remplace le trigger de migration 05 en conservant impérativement l'allowlist admin.
create or replace function public.handle_new_akademia_user()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  chosen_series text;
  approved_admin boolean;
  applicant_kind text;
  referral_owner uuid;
begin
  select exists (
    select 1 from public.akademia_admin_allowlist a
    where a.enabled and a.email = lower(trim(coalesce(new.email,'')))
  ) into approved_admin;

  if approved_admin then
    insert into public.profiles(id,email,full_name,phone,series,role,registration_status,must_change_password,password_change_required_at)
    values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',''),
      nullif(new.raw_user_meta_data->>'phone',''),'Administrateur','admin','approved',true,now())
    on conflict(id) do update set email=excluded.email, full_name=excluded.full_name,
      series='Administrateur', role='admin', registration_status='approved',
      must_change_password=true, password_change_required_at=now();
    return new;
  end if;

  applicant_kind := lower(trim(coalesce(new.raw_user_meta_data->>'candidate_type','')));
  if coalesce(new.raw_user_meta_data->>'account_kind','') = 'applicant' then
    if applicant_kind not in ('teacher','partner','promoter') then
      raise exception 'Choisissez un type de candidature valide.';
    end if;
    insert into public.profiles(id,email,full_name,phone,series,role,registration_status,requested_role)
    values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',''),
      nullif(new.raw_user_meta_data->>'phone',''),'Candidat','applicant','approved',applicant_kind)
    on conflict(id) do update set email=excluded.email, full_name=excluded.full_name,
      phone=excluded.phone, series='Candidat', role='applicant', requested_role=applicant_kind;
    return new;
  end if;

  chosen_series := nullif(trim(coalesce(new.raw_user_meta_data->>'series','')),'');
  if chosen_series is null or chosen_series not in
    ('Seconde','Première L','Première S','Première OSE','Terminale L','Terminale S','Terminale OSE') then
    raise exception 'Choisissez une classe et une série valides.';
  end if;

  if nullif(trim(coalesce(new.raw_user_meta_data->>'referral_code','')),'') is not null then
    select p.id into referral_owner from public.profiles p
    where p.role='promoter' and p.registration_status='approved'
      and p.referral_code = upper(trim(new.raw_user_meta_data->>'referral_code'))
    limit 1;
    if referral_owner is null then raise exception 'Code de parrainage inconnu ou inactif.'; end if;
  end if;

  insert into public.profiles(id,email,full_name,phone,series,role,registration_status,referred_by)
  values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',''),
    nullif(new.raw_user_meta_data->>'phone',''),chosen_series,'student','pending',referral_owner)
  on conflict(id) do update set email=excluded.email, full_name=excluded.full_name,
    phone=excluded.phone, series=excluded.series;
  return new;
end;
$$;

-- 2) Candidatures avec pièces privées.
create table if not exists public.role_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  application_type text not null check (application_type in ('teacher','partner','promoter')),
  applicant_name text not null,
  applicant_email text not null,
  phone text not null,
  specialty text,
  diploma_level text,
  organization_name text,
  monthly_commitment_accepted boolean not null default false,
  documents jsonb not null default '[]'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  review_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(user_id, application_type)
);
create index if not exists role_applications_status_created_idx on public.role_applications(status, created_at desc);
alter table public.role_applications enable row level security;
revoke all on public.role_applications from anon, public, authenticated;
grant select on public.role_applications to authenticated;
grant insert(user_id,application_type,applicant_name,applicant_email,phone,specialty,diploma_level,organization_name,monthly_commitment_accepted,documents)
  on public.role_applications to authenticated;
drop policy if exists role_applications_select_owner_admin on public.role_applications;
create policy role_applications_select_owner_admin on public.role_applications
  for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists role_applications_insert_applicant on public.role_applications;
create policy role_applications_insert_applicant on public.role_applications
  for insert to authenticated with check (
    user_id=auth.uid()
    and status='pending'
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='applicant' and p.requested_role=application_type)
    and (application_type <> 'partner' or monthly_commitment_accepted=true)
  );

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('role-application-documents','role-application-documents',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set public=false, file_size_limit=10485760,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists role_docs_insert_own on storage.objects;
create policy role_docs_insert_own on storage.objects for insert to authenticated
  with check (bucket_id='role-application-documents' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists role_docs_select_owner_admin on storage.objects;
create policy role_docs_select_owner_admin on storage.objects for select to authenticated
  using (bucket_id='role-application-documents' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
drop policy if exists role_docs_delete_own_pending on storage.objects;
create policy role_docs_delete_own_pending on storage.objects for delete to authenticated
  using (bucket_id='role-application-documents' and (storage.foldername(name))[1]=auth.uid()::text
    and not exists(select 1 from public.role_applications a where a.user_id=auth.uid()));

-- Barrières RESTRICTIVE : une ancienne politique Storage permissive ne doit pas
-- élargir les droits sur les documents de candidature.
drop policy if exists role_docs_select_guard on storage.objects;
create policy role_docs_select_guard on storage.objects as restrictive for select to authenticated
  using(bucket_id<>'role-application-documents' or (storage.foldername(name))[1]=auth.uid()::text or public.is_admin());
drop policy if exists role_docs_insert_guard on storage.objects;
create policy role_docs_insert_guard on storage.objects as restrictive for insert to authenticated
  with check(bucket_id<>'role-application-documents' or ((storage.foldername(name))[1]=auth.uid()::text
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='applicant')));
drop policy if exists role_docs_delete_guard on storage.objects;
create policy role_docs_delete_guard on storage.objects as restrictive for delete to authenticated
  using(bucket_id<>'role-application-documents' or ((storage.foldername(name))[1]=auth.uid()::text
    and not exists(select 1 from public.role_applications a where a.user_id=auth.uid())));
drop policy if exists role_docs_update_guard on storage.objects;
create policy role_docs_update_guard on storage.objects as restrictive for update to authenticated
  using(bucket_id<>'role-application-documents') with check(bucket_id<>'role-application-documents');

create or replace function public.admin_review_role_application(
  p_application_id uuid, p_decision text, p_review_note text default null
) returns text language plpgsql security definer set search_path=public
as $$
declare app public.role_applications%rowtype; code text;
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Décision invalide.'; end if;
  select * into app from public.role_applications where id=p_application_id for update;
  if not found or app.status<>'pending' then raise exception 'Candidature introuvable ou déjà traitée.'; end if;
  if p_decision='approved' and app.application_type in ('teacher','promoter') then
    if jsonb_typeof(app.documents)<>'array' or jsonb_array_length(app.documents)<2
      or not exists(select 1 from jsonb_array_elements(app.documents) d where d->>'kind'='identity_photo'
        and exists(select 1 from storage.objects o where o.bucket_id='role-application-documents' and o.name=d->>'path' and o.name like app.user_id::text||'/%'))
      or not exists(select 1 from jsonb_array_elements(app.documents) d where d->>'kind'='diploma_proof'
        and exists(select 1 from storage.objects o where o.bucket_id='role-application-documents' and o.name=d->>'path' and o.name like app.user_id::text||'/%')) then
      raise exception 'La photo d’identité et la preuve du diplôme doivent être téléversées dans le stockage privé.';
    end if;
  end if;
  if p_decision='approved' and app.application_type='teacher' and nullif(trim(app.specialty),'') is null then
    raise exception 'La spécialité proposée doit être renseignée.';
  end if;
  if p_decision='approved' and app.application_type='promoter' and app.diploma_level not in ('Baccalauréat','Bac+2','Licence','Master','Doctorat') then
    raise exception 'Le niveau de diplôme doit être au minimum le Baccalauréat.';
  end if;
  if p_decision='approved' and app.application_type='partner' and nullif(trim(app.organization_name),'') is null then
    raise exception 'Le nom du partenaire ou de l’organisme est obligatoire.';
  end if;
  update public.role_applications set status=p_decision, review_note=nullif(trim(p_review_note),''),
    reviewed_by=auth.uid(), reviewed_at=now() where id=p_application_id;
  if p_decision='approved' then
    if app.application_type='promoter' then
      loop
        code := upper(substr(encode(gen_random_bytes(8),'hex'),1,8));
        exit when not exists(select 1 from public.profiles where referral_code=code);
      end loop;
    else code := null; end if;
    update public.profiles set role=app.application_type, registration_status='approved',
      referral_code=case when app.application_type='promoter' then code else referral_code end
    where id=app.user_id and role='applicant';
    if not found then raise exception 'Profil candidat introuvable ou déjà converti.'; end if;
  end if;
  return coalesce(code,'');
end; $$;
revoke all on function public.admin_review_role_application(uuid,text,text) from public;
grant execute on function public.admin_review_role_application(uuid,text,text) to authenticated;

-- 3) Affectations enseignants : le nom de matière est confirmé par l'administrateur.
create table if not exists public.teacher_subject_assignments (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  subject_name text not null,
  target_series text[] not null default '{}',
  active boolean not null default true,
  assigned_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(teacher_id, subject_name)
);
alter table public.teacher_subject_assignments enable row level security;
revoke all on public.teacher_subject_assignments from anon, public, authenticated;
grant select on public.teacher_subject_assignments to authenticated;
drop policy if exists teacher_assignments_select_owner_admin on public.teacher_subject_assignments;
create policy teacher_assignments_select_owner_admin on public.teacher_subject_assignments
  for select to authenticated using (teacher_id=auth.uid() or public.is_admin());
drop policy if exists teacher_assignments_select_assigned_student on public.teacher_subject_assignments;
create policy teacher_assignments_select_assigned_student on public.teacher_subject_assignments
  for select to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='student' and p.series=any(target_series)));
create or replace function public.admin_assign_teacher_subject(p_teacher_id uuid,p_subject_name text,p_target_series text[])
returns uuid language plpgsql security definer set search_path=public
as $$
declare result_id uuid;
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  if not exists(select 1 from public.profiles where id=p_teacher_id and role='teacher') then raise exception 'Enseignant approuvé introuvable.'; end if;
  if nullif(trim(p_subject_name),'') is null then raise exception 'La matière doit être renseignée.'; end if;
  if p_target_series is null or cardinality(p_target_series)=0 or exists(
    select 1 from unnest(p_target_series) s where s not in ('Seconde','Première L','Première S','Première OSE','Terminale L','Terminale S','Terminale OSE')
  ) then raise exception 'Sélection de séries invalide.'; end if;
  insert into public.teacher_subject_assignments(teacher_id,subject_name,target_series,active,assigned_by)
  values(p_teacher_id,trim(p_subject_name),p_target_series,true,auth.uid())
  on conflict(teacher_id,subject_name) do update set target_series=excluded.target_series,active=true,assigned_by=auth.uid()
  returning id into result_id;
  return result_id;
end; $$;
revoke all on function public.admin_assign_teacher_subject(uuid,text,text[]) from public;
grant execute on function public.admin_assign_teacher_subject(uuid,text,text[]) to authenticated;

-- Approbation enseignant + affectation dans une seule transaction RPC.
-- Évite un compte enseignant approuvé sans matière si la seconde opération échoue.
create or replace function public.admin_finalize_teacher_application(
  p_application_id uuid, p_review_note text, p_subject_name text, p_target_series text[]
) returns uuid language plpgsql security definer set search_path=public
as $$
declare app public.role_applications%rowtype; assignment_id uuid;
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  select * into app from public.role_applications where id=p_application_id for update;
  if not found or app.status<>'pending' or app.application_type<>'teacher' then
    raise exception 'Candidature enseignant introuvable ou déjà traitée.';
  end if;
  perform public.admin_review_role_application(p_application_id,'approved',p_review_note);
  assignment_id := public.admin_assign_teacher_subject(app.user_id,p_subject_name,p_target_series);
  return assignment_id;
end; $$;
revoke all on function public.admin_finalize_teacher_application(uuid,text,text,text[]) from public;
grant execute on function public.admin_finalize_teacher_application(uuid,text,text,text[]) to authenticated;

-- 4) Partenaires : cotisation mensuelle 100 000 Ar et ticket secondaire à six chiffres.
create table if not exists public.partner_contributions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_ar integer not null default 100000 check(amount_ar=100000),
  payment_method text not null check(payment_method in ('MVola','Binance Pay')),
  payment_reference text not null check(payment_reference='FINANCEMENT'),
  transaction_reference text not null check(length(trim(transaction_reference))>=3),
  proof_path text not null,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id), reviewed_at timestamptz, created_at timestamptz not null default now()
);
create index if not exists partner_contributions_status_idx on public.partner_contributions(status,created_at desc);
alter table public.partner_contributions enable row level security;
revoke all on public.partner_contributions from anon,public,authenticated;
grant select on public.partner_contributions to authenticated;
grant insert(user_id,amount_ar,payment_method,payment_reference,transaction_reference,proof_path) on public.partner_contributions to authenticated;
drop policy if exists partner_contributions_select_owner_admin on public.partner_contributions;
create policy partner_contributions_select_owner_admin on public.partner_contributions for select to authenticated
  using(user_id=auth.uid() or public.is_admin());
drop policy if exists partner_contributions_insert_partner on public.partner_contributions;
create policy partner_contributions_insert_partner on public.partner_contributions for insert to authenticated
  with check(user_id=auth.uid() and status='pending'
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='partner')
    and proof_path like auth.uid()::text||'/%');

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('partner-payment-proofs','partner-payment-proofs',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists partner_proofs_insert_own on storage.objects;
create policy partner_proofs_insert_own on storage.objects for insert to authenticated
  with check(bucket_id='partner-payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='partner'));
drop policy if exists partner_proofs_select_owner_admin on storage.objects;
create policy partner_proofs_select_owner_admin on storage.objects for select to authenticated
  using(bucket_id='partner-payment-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- Barrières de stockage : seuls le partenaire propriétaire et l'administration voient la pièce.
drop policy if exists partner_proofs_select_guard on storage.objects;
create policy partner_proofs_select_guard on storage.objects as restrictive for select to authenticated
  using(bucket_id<>'partner-payment-proofs' or (storage.foldername(name))[1]=auth.uid()::text or public.is_admin());
drop policy if exists partner_proofs_insert_guard on storage.objects;
create policy partner_proofs_insert_guard on storage.objects as restrictive for insert to authenticated
  with check(bucket_id<>'partner-payment-proofs' or ((storage.foldername(name))[1]=auth.uid()::text
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='partner')));
drop policy if exists partner_proofs_update_guard on storage.objects;
create policy partner_proofs_update_guard on storage.objects as restrictive for update to authenticated
  using(bucket_id<>'partner-payment-proofs') with check(bucket_id<>'partner-payment-proofs');
drop policy if exists partner_proofs_delete_guard on storage.objects;
create policy partner_proofs_delete_guard on storage.objects as restrictive for delete to authenticated
  using(bucket_id<>'partner-payment-proofs');

create table if not exists public.partner_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  access_ticket text not null,
  ticket_valid_until date not null,
  contribution_expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);
create unique index if not exists partner_memberships_access_ticket_unique on public.partner_memberships(access_ticket);
alter table public.partner_memberships enable row level security;
revoke all on public.partner_memberships from anon,public,authenticated;
grant select on public.partner_memberships to authenticated;
drop policy if exists partner_memberships_select_owner_admin on public.partner_memberships;
create policy partner_memberships_select_owner_admin on public.partner_memberships for select to authenticated
  using(user_id=auth.uid() or public.is_admin());

create or replace function public.admin_decide_partner_contribution(p_contribution_id uuid,p_decision text,p_ticket_valid_until date default null)
returns text language plpgsql security definer set search_path=public
as $$
declare c public.partner_contributions%rowtype; ticket text;
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Décision invalide.'; end if;
  select * into c from public.partner_contributions where id=p_contribution_id for update;
  if not found or c.status<>'pending' then raise exception 'Cotisation introuvable ou déjà traitée.'; end if;
  if p_decision='approved' and (p_ticket_valid_until is null or p_ticket_valid_until<current_date) then
    raise exception 'La date de fin de validité du ticket annuel doit être renseignée.';
  end if;
  if p_decision='approved' and not exists(select 1 from storage.objects o where o.bucket_id='partner-payment-proofs' and o.name=c.proof_path) then
    raise exception 'Le justificatif de paiement est introuvable dans le stockage privé.';
  end if;
  update public.partner_contributions set status=p_decision,reviewed_by=auth.uid(),reviewed_at=now() where id=p_contribution_id;
  if p_decision='approved' then
    loop
      ticket := lpad((floor(random()*1000000))::bigint::text,6,'0');
      exit when not exists(select 1 from public.partner_memberships where access_ticket=ticket);
    end loop;
    insert into public.partner_memberships(user_id,access_ticket,ticket_valid_until,contribution_expires_at)
    values(c.user_id,ticket,p_ticket_valid_until,now()+interval '30 days')
    on conflict(user_id) do update set
      ticket_valid_until=greatest(public.partner_memberships.ticket_valid_until,excluded.ticket_valid_until),
      contribution_expires_at=greatest(public.partner_memberships.contribution_expires_at,now())+interval '30 days',
      updated_at=now();
    -- Le ticket n'est pas un mot de passe et ne remplace jamais Supabase Auth.
    select access_ticket into ticket from public.partner_memberships where user_id=c.user_id;
    return ticket;
  end if;
  return '';
end; $$;
revoke all on function public.admin_decide_partner_contribution(uuid,text,date) from public;
grant execute on function public.admin_decide_partner_contribution(uuid,text,date) to authenticated;

-- L'accès partenaire aux cours dépend d'une cotisation mensuelle active ET du ticket annuel valide.
create or replace function public.has_active_akademia_subscription()
returns boolean language sql stable security definer set search_path=public
as $$
  select exists(select 1 from public.subscriptions s where s.user_id=auth.uid() and s.status='actif' and s.expires_at>now())
    or exists(select 1 from public.partner_memberships m where m.user_id=auth.uid()
      and m.contribution_expires_at>now() and m.ticket_valid_until>=current_date);
$$;

-- 5) Promoteurs : referral code, commission à l'approbation de l'élève, seuil de 30 000 Ar.
create table if not exists public.promoter_commissions (
  id uuid primary key default gen_random_uuid(),
  promoter_id uuid not null references public.profiles(id) on delete cascade,
  student_id uuid not null unique references public.profiles(id) on delete cascade,
  amount_ar integer not null default 1000 check(amount_ar=1000),
  created_at timestamptz not null default now()
);
alter table public.promoter_commissions enable row level security;
revoke all on public.promoter_commissions from anon,public,authenticated;
grant select on public.promoter_commissions to authenticated;
drop policy if exists promoter_commissions_select_owner_admin on public.promoter_commissions;
create policy promoter_commissions_select_owner_admin on public.promoter_commissions for select to authenticated
  using(promoter_id=auth.uid() or public.is_admin());

create or replace function public.record_akademia_promoter_commission()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if new.role='student' and new.registration_status='approved' and new.referred_by is not null then
    if tg_op='INSERT' or (tg_op='UPDATE' and old.registration_status is distinct from new.registration_status) then
      insert into public.promoter_commissions(promoter_id,student_id,amount_ar)
      select new.referred_by,new.id,1000
      where exists(select 1 from public.profiles p where p.id=new.referred_by and p.role='promoter' and p.registration_status='approved')
      on conflict(student_id) do nothing;
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists trg_akademia_promoter_commission on public.profiles;
create trigger trg_akademia_promoter_commission after insert or update of registration_status on public.profiles
for each row execute function public.record_akademia_promoter_commission();

-- 6) Travail enseignant validé par l'admin; 6 000 Ar par journée déclarée.
create table if not exists public.teacher_work_days (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  work_date date not null,
  note text,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(teacher_id,work_date)
);
alter table public.teacher_work_days enable row level security;
revoke all on public.teacher_work_days from anon,public,authenticated;
grant select on public.teacher_work_days to authenticated;
drop policy if exists teacher_work_days_select_owner_admin on public.teacher_work_days;
create policy teacher_work_days_select_owner_admin on public.teacher_work_days for select to authenticated
  using(teacher_id=auth.uid() or public.is_admin());
create or replace function public.admin_record_teacher_work_day(p_teacher_id uuid,p_work_date date,p_note text default null)
returns uuid language plpgsql security definer set search_path=public
as $$
declare work_id uuid;
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  if p_work_date>current_date then raise exception 'Une journée future ne peut pas être comptabilisée comme journée travaillée.'; end if;
  if not exists(select 1 from public.profiles where id=p_teacher_id and role='teacher') then raise exception 'Enseignant introuvable.'; end if;
  insert into public.teacher_work_days(teacher_id,work_date,note,recorded_by)
  values(p_teacher_id,p_work_date,nullif(trim(p_note),''),auth.uid())
  on conflict(teacher_id,work_date) do update set note=excluded.note,recorded_by=auth.uid()
  returning id into work_id;
  return work_id;
end; $$;
revoke all on function public.admin_record_teacher_work_day(uuid,date,text) from public;
grant execute on function public.admin_record_teacher_work_day(uuid,date,text) to authenticated;

create table if not exists public.finance_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  request_type text not null check(request_type in ('teacher_salary','teacher_advance','promoter_payout')),
  period_month date,
  amount_ar integer not null check(amount_ar>0),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  transfer_reference text,
  review_note text,
  reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists finance_requests_user_created_idx on public.finance_requests(user_id,created_at desc);
alter table public.finance_requests enable row level security;
revoke all on public.finance_requests from anon,public,authenticated;
grant select on public.finance_requests to authenticated;
drop policy if exists finance_requests_select_owner_admin on public.finance_requests;
create policy finance_requests_select_owner_admin on public.finance_requests for select to authenticated
  using(user_id=auth.uid() or public.is_admin());

create or replace function public.create_akademia_finance_request(p_request_type text,p_period_month date default null)
returns uuid language plpgsql security definer set search_path=public
as $$
declare who uuid:=auth.uid(); r public.profiles%rowtype; amount_due bigint; request_id uuid; period_start date;
begin
  if who is null then raise exception 'Connexion requise.'; end if;
  select * into r from public.profiles where id=who for update;
  if not found then raise exception 'Profil introuvable.'; end if;
  if p_request_type='teacher_salary' then
    if r.role<>'teacher' or p_period_month is null then raise exception 'Demande de salaire enseignant invalide.'; end if;
    period_start:=date_trunc('month',p_period_month)::date;
    -- La réclamation mensuelle porte sur le cumul non encore réclamé : les avances antérieures
    -- sont également déduites pour empêcher tout double paiement du même salaire acquis.
    select count(*)*6000 into amount_due from public.teacher_work_days
      where teacher_id=who and work_date < (period_start + interval '1 month')::date;
    select amount_due-coalesce(sum(amount_ar),0) into amount_due from public.finance_requests
      where user_id=who and status in ('pending','approved')
        and (request_type='teacher_advance' or (request_type='teacher_salary' and period_month<=period_start));
  elsif p_request_type='teacher_advance' then
    if r.role<>'teacher' then raise exception 'Demande réservée aux enseignants.'; end if;
    select count(*)*6000 into amount_due from public.teacher_work_days where teacher_id=who;
    select amount_due-coalesce(sum(amount_ar),0) into amount_due from public.finance_requests
      where user_id=who and request_type in ('teacher_salary','teacher_advance') and status in ('pending','approved');
  elsif p_request_type='promoter_payout' then
    if r.role<>'promoter' then raise exception 'Demande réservée aux promoteurs.'; end if;
    select coalesce(sum(c.amount_ar),0) into amount_due from public.promoter_commissions c where c.promoter_id=who;
    select amount_due-coalesce(sum(amount_ar),0) into amount_due from public.finance_requests
      where user_id=who and request_type='promoter_payout' and status in ('pending','approved');
  else raise exception 'Type de demande inconnu.'; end if;
  if amount_due<=0 then raise exception 'Aucun montant disponible à réclamer.'; end if;
  if p_request_type in ('teacher_advance','promoter_payout') and amount_due<30000 then
    raise exception 'Le solde disponible doit atteindre au moins 30 000 Ar.';
  end if;
  insert into public.finance_requests(user_id,request_type,period_month,amount_ar)
  values(who,p_request_type,case when p_request_type='teacher_salary' then period_start else null end,amount_due::integer)
  returning id into request_id;
  return request_id;
end; $$;
revoke all on function public.create_akademia_finance_request(text,date) from public;
grant execute on function public.create_akademia_finance_request(text,date) to authenticated;

create or replace function public.admin_review_finance_request(p_request_id uuid,p_decision text,p_transfer_reference text default null,p_review_note text default null)
returns boolean language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Décision invalide.'; end if;
  if p_decision='approved' and nullif(trim(p_transfer_reference),'') is null then raise exception 'Renseignez la référence de virement réellement effectué.'; end if;
  update public.finance_requests set status=p_decision,transfer_reference=nullif(trim(p_transfer_reference),''),
    review_note=nullif(trim(p_review_note),''),reviewed_by=auth.uid(),reviewed_at=now()
  where id=p_request_id and status='pending';
  if not found then raise exception 'Demande introuvable ou déjà traitée.'; end if;
  return true;
end; $$;
revoke all on function public.admin_review_finance_request(uuid,text,text,text) from public;
grant execute on function public.admin_review_finance_request(uuid,text,text,text) to authenticated;

-- 7) Demandes administratives enseignant.
create table if not exists public.staff_requests (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  request_type text not null check(request_type in ('leave','replacement','resignation')),
  start_date date,
  end_date date,
  location text,
  replacement_teacher_id uuid references public.profiles(id),
  reason text not null,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id),reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.staff_requests enable row level security;
revoke all on public.staff_requests from anon,public,authenticated;
grant select on public.staff_requests to authenticated;
grant insert(teacher_id,request_type,start_date,end_date,location,replacement_teacher_id,reason) on public.staff_requests to authenticated;
drop policy if exists staff_requests_select_owner_admin on public.staff_requests;
create policy staff_requests_select_owner_admin on public.staff_requests for select to authenticated
  using(teacher_id=auth.uid() or public.is_admin());
drop policy if exists staff_requests_insert_teacher on public.staff_requests;
create policy staff_requests_insert_teacher on public.staff_requests for insert to authenticated
  with check(teacher_id=auth.uid() and status='pending' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='teacher')
    and (request_type not in ('leave','replacement') or (start_date is not null and end_date is not null and end_date>=start_date))
    and (request_type<>'leave' or nullif(trim(location),'') is not null)
    and (request_type<>'replacement' or replacement_teacher_id is not null)
    and (replacement_teacher_id is null or (replacement_teacher_id<>auth.uid() and exists(
      select 1 from public.profiles rp join public.teacher_subject_assignments ra on ra.teacher_id=rp.id and ra.active
      join public.teacher_subject_assignments mine on mine.teacher_id=auth.uid() and mine.active
      where rp.id=replacement_teacher_id and rp.role='teacher' and rp.registration_status='approved'
        and ra.target_series && mine.target_series))));
create or replace function public.admin_review_staff_request(p_request_id uuid,p_decision text,p_admin_note text default null)
returns boolean language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Décision invalide.'; end if;
  update public.staff_requests set status=p_decision,admin_note=nullif(trim(p_admin_note),''),reviewed_by=auth.uid(),reviewed_at=now()
    where id=p_request_id and status='pending';
  if not found then raise exception 'Demande introuvable ou déjà traitée.'; end if;
  return true;
end; $$;
revoke all on function public.admin_review_staff_request(uuid,text,text) from public;
grant execute on function public.admin_review_staff_request(uuid,text,text) to authenticated;

-- 8) Ressources pédagogiques envoyées par les enseignants (PDF/DOC/DOCX).
create table if not exists public.teacher_resources (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  subject_name text not null,
  title text not null,
  description text,
  resource_type text not null check(resource_type in ('course','exercise','evaluation')),
  target_series text[] not null default '{}',
  due_at timestamptz,
  file_path text not null,
  published boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.teacher_resources enable row level security;
revoke all on public.teacher_resources from anon,public,authenticated;
grant select on public.teacher_resources to authenticated;
grant insert(teacher_id,subject_name,title,description,resource_type,target_series,due_at,file_path) on public.teacher_resources to authenticated;
drop policy if exists teacher_resources_select_policy on public.teacher_resources;
create policy teacher_resources_select_policy on public.teacher_resources for select to authenticated
  using(public.is_admin() or teacher_id=auth.uid() or
    (published and public.has_active_akademia_subscription() and exists(
      select 1 from public.profiles p join public.teacher_subject_assignments a on a.teacher_id=teacher_resources.teacher_id
      where p.id=auth.uid() and p.role='student' and p.series=any(teacher_resources.target_series)
        and a.active and a.subject_name=teacher_resources.subject_name and p.series=any(a.target_series)
    )));
drop policy if exists teacher_resources_insert_teacher on public.teacher_resources;
create policy teacher_resources_insert_teacher on public.teacher_resources for insert to authenticated
  with check(teacher_id=auth.uid() and file_path like auth.uid()::text||'/%'
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='teacher')
    and exists(select 1 from public.teacher_subject_assignments a where a.teacher_id=auth.uid() and a.active
      and a.subject_name=teacher_resources.subject_name and teacher_resources.target_series <@ a.target_series));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('teacher-course-files','teacher-course-files',false,20971520,
 array['application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set public=false,file_size_limit=20971520,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists teacher_files_insert_own on storage.objects;
create policy teacher_files_insert_own on storage.objects for insert to authenticated
  with check(bucket_id='teacher-course-files' and (storage.foldername(name))[1]=auth.uid()::text
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='teacher'));
drop policy if exists teacher_files_select_own_admin on storage.objects;
create policy teacher_files_select_own_admin on storage.objects for select to authenticated
  using(bucket_id='teacher-course-files' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- Les règles restrictives couvrent également les cas où d'autres politiques Storage existent.
drop policy if exists teacher_files_select_guard on storage.objects;
create policy teacher_files_select_guard on storage.objects as restrictive for select to authenticated
  using(bucket_id<>'teacher-course-files' or (storage.foldername(name))[1]=auth.uid()::text or public.is_admin()
    or exists(select 1 from public.teacher_resources tr join public.profiles p on p.id=auth.uid()
      where tr.file_path=storage.objects.name and tr.published and p.role='student'
        and p.series=any(tr.target_series) and public.has_active_akademia_subscription()));
drop policy if exists teacher_files_insert_guard on storage.objects;
create policy teacher_files_insert_guard on storage.objects as restrictive for insert to authenticated
  with check(bucket_id<>'teacher-course-files' or ((storage.foldername(name))[1]=auth.uid()::text
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='teacher')));
drop policy if exists teacher_files_update_guard on storage.objects;
create policy teacher_files_update_guard on storage.objects as restrictive for update to authenticated
  using(bucket_id<>'teacher-course-files') with check(bucket_id<>'teacher-course-files');
drop policy if exists teacher_files_delete_guard on storage.objects;
create policy teacher_files_delete_guard on storage.objects as restrictive for delete to authenticated
  using(bucket_id<>'teacher-course-files');

-- 9) Messagerie privée multi-rôles; messages élève-élève limités à la même série.
create table if not exists public.role_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  subject text not null,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  check(sender_id<>recipient_id)
);
create index if not exists role_messages_conversation_idx on public.role_messages(sender_id,recipient_id,created_at desc);
alter table public.role_messages enable row level security;
revoke all on public.role_messages from anon,public,authenticated;
grant select on public.role_messages to authenticated;
grant update(read_at) on public.role_messages to authenticated;
drop policy if exists role_messages_select_participants_admin on public.role_messages;
create policy role_messages_select_participants_admin on public.role_messages for select to authenticated
  using(sender_id=auth.uid() or recipient_id=auth.uid() or public.is_admin());
drop policy if exists role_messages_update_recipient_read on public.role_messages;
create policy role_messages_update_recipient_read on public.role_messages for update to authenticated
  using(recipient_id=auth.uid()) with check(recipient_id=auth.uid());
create or replace function public.send_akademia_message(p_recipient_id uuid,p_subject text,p_body text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare s public.profiles%rowtype; r public.profiles%rowtype; new_id uuid; allowed boolean:=false;
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  if nullif(trim(p_subject),'') is null or length(trim(p_body))<2 or length(p_body)>10000 then raise exception 'Sujet ou message invalide.'; end if;
  select * into s from public.profiles where id=auth.uid();
  select * into r from public.profiles where id=p_recipient_id;
  if not found then raise exception 'Destinataire introuvable.'; end if;
  if s.role='admin' then allowed:=true;
  elsif s.role in ('partner','promoter') then allowed:=(r.role='admin');
  elsif s.role='student' and r.role='student' then allowed:=(s.series=r.series);
  elsif s.role='student' and r.role='teacher' then
    allowed:=exists(select 1 from public.teacher_subject_assignments a where a.teacher_id=r.id and a.active and s.series=any(a.target_series));
  elsif s.role='teacher' and r.role='student' then
    allowed:=exists(select 1 from public.teacher_subject_assignments a where a.teacher_id=s.id and a.active and r.series=any(a.target_series));
  elsif s.role='teacher' and r.role in ('teacher','admin') then allowed:=true;
  end if;
  if not allowed then raise exception 'La messagerie ne permet pas cet échange entre ces profils.'; end if;
  insert into public.role_messages(sender_id,recipient_id,subject,body)
    values(auth.uid(),p_recipient_id,trim(p_subject),trim(p_body)) returning id into new_id;
  return new_id;
end; $$;
revoke all on function public.send_akademia_message(uuid,text,text) from public;
grant execute on function public.send_akademia_message(uuid,text,text) to authenticated;

-- Donner accès aux fichiers publiés aux élèves abonnés affectés à la série.
drop policy if exists teacher_files_select_student_published on storage.objects;
create policy teacher_files_select_student_published on storage.objects for select to authenticated
  using(bucket_id='teacher-course-files' and exists(
    select 1 from public.teacher_resources tr
    join public.profiles p on p.id=auth.uid()
    where tr.file_path=storage.objects.name and tr.published
      and p.role='student' and p.series=any(tr.target_series)
      and public.has_active_akademia_subscription()
  ));

create or replace function public.admin_publish_teacher_resource(p_resource_id uuid,p_publish boolean)
returns boolean language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Action réservée à l’administrateur.'; end if;
  update public.teacher_resources set published=p_publish where id=p_resource_id;
  if not found then raise exception 'Ressource introuvable.'; end if;
  return true;
end; $$;
revoke all on function public.admin_publish_teacher_resource(uuid,boolean) from public;
grant execute on function public.admin_publish_teacher_resource(uuid,boolean) to authenticated;

-- Annuaire privé des destinataires autorisés pour éviter de publier les profils.
create or replace function public.list_akademia_message_contacts()
returns table(user_id uuid, full_name text, role text, series text)
language plpgsql stable security definer set search_path=public
as $$
declare me public.profiles%rowtype;
begin
  select * into me from public.profiles where id=auth.uid();
  if not found then raise exception 'Profil introuvable.'; end if;
  return query
  select p.id,p.full_name,p.role,p.series from public.profiles p
  where p.id<>auth.uid() and p.registration_status='approved' and (
    me.role='admin'
    or (me.role in ('partner','promoter') and p.role='admin')
    or (me.role='student' and p.role='student' and p.series=me.series)
    or (me.role='student' and p.role='teacher' and exists(select 1 from public.teacher_subject_assignments a where a.teacher_id=p.id and a.active and me.series=any(a.target_series)))
    or (me.role='teacher' and p.role in ('teacher','admin'))
    or (me.role='teacher' and p.role='student' and exists(select 1 from public.teacher_subject_assignments a where a.teacher_id=me.id and a.active and p.series=any(a.target_series)))
  ) order by p.role,p.full_name;
end; $$;
revoke all on function public.list_akademia_message_contacts() from public;
grant execute on function public.list_akademia_message_contacts() to authenticated;

-- Rapports limités aux séries affectées du professeur.
create or replace function public.list_teacher_student_progress()
returns table(student_id uuid,full_name text,email text,series text,completed_count bigint,recorded_count bigint,last_activity timestamptz)
language plpgsql stable security definer set search_path=public
as $$
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='teacher' and p.registration_status='approved') then
    raise exception 'Cette vue est réservée aux enseignants approuvés.';
  end if;
  return query
  select st.id,st.full_name,st.email,st.series,
    count(sp.lesson_id) filter(where sp.completed),count(sp.lesson_id),max(sp.updated_at)
  from public.profiles st
  left join public.student_progress sp on sp.user_id=st.id
  where st.role='student' and st.registration_status='approved'
    and exists(select 1 from public.teacher_subject_assignments a where a.teacher_id=auth.uid() and a.active and st.series=any(a.target_series))
  group by st.id,st.full_name,st.email,st.series
  order by count(sp.lesson_id) filter(where sp.completed) desc,st.full_name;
end; $$;
revoke all on function public.list_teacher_student_progress() from public;
grant execute on function public.list_teacher_student_progress() to authenticated;

-- Annuaire des remplaçants potentiels : enseignants approuvés partageant une série.
create or replace function public.list_akademia_replacement_teachers()
returns table(teacher_id uuid,teacher_name text)
language plpgsql stable security definer set search_path=public
as $$
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='teacher' and p.registration_status='approved') then
    raise exception 'Cette liste est réservée aux enseignants approuvés.';
  end if;
  return query
  select distinct t.id,t.full_name
  from public.profiles t
  join public.teacher_subject_assignments other_a on other_a.teacher_id=t.id and other_a.active
  where t.role='teacher' and t.registration_status='approved' and t.id<>auth.uid()
    and exists(select 1 from public.teacher_subject_assignments mine
      where mine.teacher_id=auth.uid() and mine.active and mine.target_series && other_a.target_series)
  order by t.full_name;
end; $$;
revoke all on function public.list_akademia_replacement_teachers() from public;
grant execute on function public.list_akademia_replacement_teachers() to authenticated;

-- Un promoteur voit les noms et séries des seuls élèves réellement rattachés à son code.
create or replace function public.list_akademia_promoter_referrals()
returns table(student_id uuid,student_name text,series text,commission_ar integer,approved_at timestamptz)
language plpgsql stable security definer set search_path=public
as $$
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='promoter' and p.registration_status='approved') then
    raise exception 'Cette vue est réservée aux promoteurs approuvés.';
  end if;
  return query
  select st.id,st.full_name,st.series,c.amount_ar,c.created_at
  from public.promoter_commissions c join public.profiles st on st.id=c.student_id
  where c.promoter_id=auth.uid() and st.role='student' and st.registration_status='approved'
  order by c.created_at desc;
end; $$;
revoke all on function public.list_akademia_promoter_referrals() from public;
grant execute on function public.list_akademia_promoter_referrals() to authenticated;

-- Les partenaires actifs peuvent consulter les cours pour audit ; ils ne disposent pas
-- des fonctions de suivi ou de progression des élèves.
create or replace function public.can_access_akademia_lesson(p_lesson_id text)
returns boolean language sql stable security definer set search_path=public
as $$
  select public.is_admin()
    or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='partner'
      and exists(select 1 from public.partner_memberships m where m.user_id=p.id
        and m.contribution_expires_at>now() and m.ticket_valid_until>=current_date))
    or (public.has_active_akademia_subscription() and exists(
      select 1 from public.profiles p join public.course_release_schedule r on r.series=p.series
      where p.id=auth.uid() and p.role='student' and r.lesson_id=p_lesson_id and r.release_at<=now()
    ));
$$;
revoke all on function public.can_access_akademia_lesson(text) from public;
grant execute on function public.can_access_akademia_lesson(text) to authenticated;

-- Les partenaires actifs peuvent lire le calendrier de cours utilisé pour leur audit.
drop policy if exists course_schedule_select_own_series_or_admin on public.course_release_schedule;
create policy course_schedule_select_own_series_or_admin on public.course_release_schedule for select to authenticated
  using(public.is_admin()
    or (public.has_active_akademia_subscription() and series=(select p.series from public.profiles p where p.id=auth.uid() and p.role='student'))
    or exists(select 1 from public.profiles p join public.partner_memberships m on m.user_id=p.id
      where p.id=auth.uid() and p.role='partner' and m.contribution_expires_at>now() and m.ticket_valid_until>=current_date)
    or exists(select 1 from public.profiles p join public.teacher_subject_assignments a on a.teacher_id=p.id
      where p.id=auth.uid() and p.role='teacher' and p.registration_status='approved'
        and a.active and course_release_schedule.series=any(a.target_series)));

-- 10) Revue de cohérence et droits.
-- Les profils applicant ne reçoivent aucun accès élève : le code client doit router selon role.
-- is_admin() existant reste la seule autorité d'administration.

commit;

-- Résumé de vérification post-migration (lecture seule).
select role, count(*) as profils from public.profiles group by role order by role;
select status, application_type, count(*) as candidatures from public.role_applications group by status, application_type order by application_type,status;
