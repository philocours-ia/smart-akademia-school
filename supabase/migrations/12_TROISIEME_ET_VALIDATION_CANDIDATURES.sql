-- SMART AKADEMIA SCHOOL — Migration 12
-- Normalisation des séries actives, RPC de décision des candidatures et affectations.
-- Prérequis : migrations 01 à 10 déjà appliquées.
-- La migration 11 est un diagnostic en lecture seule.
-- Les anciennes séries restent autorisées dans les données pour préserver les anciens comptes.
-- Les nouvelles inscriptions et affectations sont limitées à Troisième (T9) et Terminale L/S/OSE.

begin;

-- 1) Mettre à jour explicitement les contraintes qui portent une série.
--    Les anciennes valeurs restent présentes pour assurer la compatibilité historique.
alter table public.profiles drop constraint if exists profiles_series_check;
alter table public.profiles
  add constraint profiles_series_check
  check (series in (
    'Troisième','Seconde','Première','Première L','Première S','Première OSE',
    'Terminale L','Terminale S','Terminale OSE','Administrateur','Candidat'
  ));

alter table public.subscriptions drop constraint if exists subscriptions_series_check;
alter table public.subscriptions
  add constraint subscriptions_series_check
  check (series in (
    'Troisième','Seconde','Première','Première L','Première S','Première OSE',
    'Terminale L','Terminale S','Terminale OSE'
  ));

alter table public.student_messages drop constraint if exists student_messages_series_check;
alter table public.student_messages
  add constraint student_messages_series_check
  check (series in (
    'Troisième','Seconde','Première','Première L','Première S','Première OSE',
    'Terminale L','Terminale S','Terminale OSE'
  ));

alter table public.course_release_schedule drop constraint if exists course_release_schedule_series_check;
alter table public.course_release_schedule
  add constraint course_release_schedule_series_check
  check (series in (
    'Troisième','Seconde','Première','Première L','Première S','Première OSE',
    'Terminale L','Terminale S','Terminale OSE'
  ));

-- Une candidature rejetée peut être corrigée puis redéposée sur le même compte.
-- Une seule candidature en attente est autorisée par type et par compte.
alter table public.role_applications
  drop constraint if exists role_applications_user_id_application_type_key;
drop index if exists public.role_applications_one_pending_per_type;
create unique index role_applications_one_pending_per_type
  on public.role_applications(user_id,application_type)
  where status='pending';

-- 2) Une seule source de vérité pour les nouvelles inscriptions.
--    Les profils administrateur et candidat conservent leur traitement dédié.
create or replace function public.handle_new_akademia_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  chosen_series text;
  approved_admin boolean;
  applicant_kind text;
  referral_owner uuid;
begin
  select exists (
    select 1
    from public.akademia_admin_allowlist a
    where a.enabled and a.email = lower(trim(coalesce(new.email,'')))
  ) into approved_admin;

  if approved_admin then
    insert into public.profiles(
      id,email,full_name,phone,series,role,registration_status,
      must_change_password,password_change_required_at
    )
    values(
      new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',''),
      nullif(new.raw_user_meta_data->>'phone',''),'Administrateur','admin','approved',true,now()
    )
    on conflict(id) do update set
      email=excluded.email,
      full_name=excluded.full_name,
      series='Administrateur',
      role='admin',
      registration_status='approved',
      must_change_password=true,
      password_change_required_at=now();
    return new;
  end if;

  applicant_kind := lower(trim(coalesce(new.raw_user_meta_data->>'candidate_type','')));
  if coalesce(new.raw_user_meta_data->>'account_kind','') = 'applicant' then
    if applicant_kind not in ('teacher','partner','promoter') then
      raise exception 'Choisissez un type de candidature valide.';
    end if;

    insert into public.profiles(
      id,email,full_name,phone,series,role,registration_status,requested_role
    )
    values(
      new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',''),
      nullif(new.raw_user_meta_data->>'phone',''),'Candidat','applicant','approved',applicant_kind
    )
    on conflict(id) do update set
      email=excluded.email,
      full_name=excluded.full_name,
      phone=excluded.phone,
      series='Candidat',
      role='applicant',
      registration_status='approved',
      requested_role=applicant_kind;
    return new;
  end if;

  chosen_series := nullif(trim(coalesce(new.raw_user_meta_data->>'series','')),'');
  if chosen_series is null or chosen_series not in (
    'Troisième','Terminale L','Terminale S','Terminale OSE'
  ) then
    raise exception 'Les nouvelles inscriptions sont ouvertes à Troisième (T9) et Terminale L, S ou OSE.';
  end if;

  if nullif(trim(coalesce(new.raw_user_meta_data->>'referral_code','')),'') is not null then
    select p.id into referral_owner
    from public.profiles p
    where p.role='promoter'
      and p.registration_status='approved'
      and p.referral_code=upper(trim(new.raw_user_meta_data->>'referral_code'))
    limit 1;

    if referral_owner is null then
      raise exception 'Code de parrainage inconnu ou inactif.';
    end if;
  end if;

  insert into public.profiles(
    id,email,full_name,phone,series,role,registration_status,referred_by
  )
  values(
    new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',''),
    nullif(new.raw_user_meta_data->>'phone',''),chosen_series,'student','pending',referral_owner
  )
  on conflict(id) do update set
    email=excluded.email,
    full_name=excluded.full_name,
    phone=excluded.phone,
    series=excluded.series;

  return new;
end;
$;
-- Cette fonction n'est appelée que par le trigger Auth ; elle ne doit pas exposer
-- un point d'entrée RPC public ou directement appelable par un client.
revoke all on function public.handle_new_akademia_user() from public,anon,authenticated;

-- 3) Les affectations créées après cette migration utilisent uniquement les séries actives.
--    Les lignes historiques restent conservées et consultables par les anciens élèves concernés.
create or replace function public.admin_assign_teacher_subject(
  p_teacher_id uuid,
  p_subject_name text,
  p_target_series text[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  result_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Action réservée à l’administrateur.';
  end if;

  if not exists (
    select 1 from public.profiles
    where id=p_teacher_id and role='teacher' and registration_status='approved'
  ) then
    raise exception 'Enseignant approuvé introuvable.';
  end if;

  if nullif(trim(p_subject_name),'') is null then
    raise exception 'La matière doit être renseignée.';
  end if;

  if p_target_series is null
     or cardinality(p_target_series)=0
     or exists (
       select 1
       from unnest(p_target_series) s
       where s not in ('Troisième','Terminale L','Terminale S','Terminale OSE')
     ) then
    raise exception 'Les nouvelles affectations concernent Troisième et Terminale L/S/OSE.';
  end if;

  insert into public.teacher_subject_assignments(
    teacher_id,subject_name,target_series,active,assigned_by
  )
  values(p_teacher_id,trim(p_subject_name),p_target_series,true,auth.uid())
  on conflict(teacher_id,subject_name) do update set
    target_series=excluded.target_series,
    active=true,
    assigned_by=auth.uid()
  returning id into result_id;

  return result_id;
end;
$$;
revoke all on function public.admin_assign_teacher_subject(uuid,text,text[]) from public,anon;
grant execute on function public.admin_assign_teacher_subject(uuid,text,text[]) to authenticated;

-- 4) RPC unique appelée par le tableau de bord pour valider/refuser les candidatures.
--    L'approbation d'un enseignant et son affectation restent dans une seule transaction.
create or replace function public.admin_decide_role_application(
  p_application_id uuid,
  p_decision text,
  p_review_note text default null,
  p_subject_name text default null,
  p_target_series text[] default '{}'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  app public.role_applications%rowtype;
  assignment_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Action réservée à l’administration.';
  end if;

  if p_decision not in ('approved','rejected') then
    raise exception 'Décision administrative invalide.';
  end if;

  select * into app
  from public.role_applications
  where id=p_application_id
  for update;

  if not found or app.status<>'pending' then
    raise exception 'Candidature introuvable ou déjà traitée.';
  end if;

  if app.application_type='teacher' and p_decision='approved' then
    if nullif(trim(p_subject_name),'') is null
       or p_target_series is null
       or cardinality(p_target_series)=0 then
      raise exception 'Confirmez la matière et au moins une série avant d’approuver un enseignant.';
    end if;

    assignment_id := public.admin_finalize_teacher_application(
      p_application_id,
      p_review_note,
      p_subject_name,
      p_target_series
    );
    return assignment_id::text;
  end if;

  return public.admin_review_role_application(
    p_application_id,
    p_decision,
    p_review_note
  );
end;
$$;
revoke all on function public.admin_decide_role_application(uuid,text,text,text,text[]) from public,anon;
grant execute on function public.admin_decide_role_application(uuid,text,text,text,text[]) to authenticated;

-- 5) Liste minimale des enseignants affectés au compte élève courant.
--    Aucun e-mail, numéro de téléphone ou autre donnée privée n'est exposé.
create or replace function public.get_my_course_assignments()
returns table (
  teacher_name text,
  subject_name text,
  target_series text[]
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text;
  caller_status text;
  caller_series text;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;

  select p.role,p.registration_status,p.series
    into caller_role,caller_status,caller_series
  from public.profiles p
  where p.id=auth.uid();

  if coalesce(caller_role,'') <> 'student'
     or coalesce(caller_status,'') <> 'approved'
     or nullif(trim(caller_series),'') is null then
    return;
  end if;

  return query
    select
      coalesce(nullif(trim(t.full_name),''),'Enseignant affecté')::text,
      a.subject_name::text,
      a.target_series
    from public.teacher_subject_assignments a
    join public.profiles t on t.id=a.teacher_id
    where a.active=true
      and caller_series=any(a.target_series)
      and t.role='teacher'
      and t.registration_status='approved'
    order by a.subject_name,t.full_name;
end;
$$;
revoke all on function public.get_my_course_assignments() from public,anon;
grant execute on function public.get_my_course_assignments() to authenticated;

commit;

-- Contrôles en lecture seule après exécution :
-- select proname from pg_proc where pronamespace='public'::regnamespace
--   and proname in ('admin_decide_role_application','get_my_course_assignments');
-- select role,series,count(*) from public.profiles group by role,series order by role,series;
