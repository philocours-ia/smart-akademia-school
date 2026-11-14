-- SMART AKADEMIA SCHOOL — Migration 07
-- Dossier annuel d'inscription : photo d'identité + preuve MVola de 2 000 Ar.
-- Prérequis : migrations 01, 02, 03, 05 et 06 exécutées.
-- KYC facial non inclus : nécessite un prestataire, une base légale et un consentement dédiés.

begin;

create table if not exists public.student_enrollment_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_ar integer not null default 2000 check (amount_ar=2000),
  payment_method text not null default 'MVola' check (payment_method='MVola'),
  payment_reference text not null default 'AKADEMIA_DROIT' check (payment_reference='AKADEMIA_DROIT'),
  transaction_reference text not null check (length(trim(transaction_reference))>=3),
  identity_photo_path text not null,
  payment_proof_path text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  review_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists student_enrollment_user_created_idx
  on public.student_enrollment_submissions(user_id,created_at desc);
create index if not exists student_enrollment_status_created_idx
  on public.student_enrollment_submissions(status,created_at desc);
create unique index if not exists student_enrollment_one_pending_per_user
  on public.student_enrollment_submissions(user_id) where status='pending';

alter table public.student_enrollment_submissions enable row level security;
revoke all on public.student_enrollment_submissions from anon,public,authenticated;
grant select on public.student_enrollment_submissions to authenticated;
grant insert(user_id,amount_ar,payment_method,payment_reference,transaction_reference,identity_photo_path,payment_proof_path)
  on public.student_enrollment_submissions to authenticated;
drop policy if exists student_enrollment_select_owner_admin on public.student_enrollment_submissions;
create policy student_enrollment_select_owner_admin on public.student_enrollment_submissions
  for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists student_enrollment_insert_pending_student on public.student_enrollment_submissions;
create policy student_enrollment_insert_pending_student on public.student_enrollment_submissions
  for insert to authenticated with check(
    user_id=auth.uid() and amount_ar=2000 and payment_method='MVola'
    and payment_reference='AKADEMIA_DROIT' and status='pending'
    and identity_photo_path like auth.uid()::text||'/%'
    and payment_proof_path like auth.uid()::text||'/%'
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='student'
      and p.registration_status in ('pending','rejected'))
  );

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('student-enrollment-documents','student-enrollment-documents',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists student_enrollment_docs_insert_own on storage.objects;
create policy student_enrollment_docs_insert_own on storage.objects for insert to authenticated
  with check(bucket_id='student-enrollment-documents' and (storage.foldername(name))[1]=auth.uid()::text
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='student'
      and p.registration_status in ('pending','rejected')));
drop policy if exists student_enrollment_docs_select_owner_admin on storage.objects;
create policy student_enrollment_docs_select_owner_admin on storage.objects for select to authenticated
  using(bucket_id='student-enrollment-documents' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
drop policy if exists student_enrollment_docs_delete_unsubmitted on storage.objects;
create policy student_enrollment_docs_delete_unsubmitted on storage.objects for delete to authenticated
  using(bucket_id='student-enrollment-documents' and (storage.foldername(name))[1]=auth.uid()::text
    and not exists(select 1 from public.student_enrollment_submissions e where e.user_id=auth.uid()
      and (e.identity_photo_path=storage.objects.name or e.payment_proof_path=storage.objects.name)));

-- Barrières restrictives de défense en profondeur pour les dossiers d'inscription.
drop policy if exists student_enrollment_docs_select_guard on storage.objects;
create policy student_enrollment_docs_select_guard on storage.objects as restrictive for select to authenticated
  using(bucket_id<>'student-enrollment-documents' or (storage.foldername(name))[1]=auth.uid()::text or public.is_admin());
drop policy if exists student_enrollment_docs_insert_guard on storage.objects;
create policy student_enrollment_docs_insert_guard on storage.objects as restrictive for insert to authenticated
  with check(bucket_id<>'student-enrollment-documents' or ((storage.foldername(name))[1]=auth.uid()::text
    and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='student'
      and p.registration_status in ('pending','rejected'))));
drop policy if exists student_enrollment_docs_update_guard on storage.objects;
create policy student_enrollment_docs_update_guard on storage.objects as restrictive for update to authenticated
  using(bucket_id<>'student-enrollment-documents') with check(bucket_id<>'student-enrollment-documents');
drop policy if exists student_enrollment_docs_delete_guard on storage.objects;
create policy student_enrollment_docs_delete_guard on storage.objects as restrictive for delete to authenticated
  using(bucket_id<>'student-enrollment-documents' or ((storage.foldername(name))[1]=auth.uid()::text
    and not exists(select 1 from public.student_enrollment_submissions e where e.user_id=auth.uid()
      and (e.identity_photo_path=storage.objects.name or e.payment_proof_path=storage.objects.name))));

-- Une nouvelle preuve après un refus remet le dossier élève en attente, sans lui ouvrir les cours.
create or replace function public.mark_student_enrollment_pending()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  update public.profiles set registration_status='pending'
    where id=new.user_id and role='student' and registration_status='rejected';
  return new;
end; $$;
revoke all on function public.mark_student_enrollment_pending() from public;
drop trigger if exists trg_student_enrollment_pending on public.student_enrollment_submissions;
create trigger trg_student_enrollment_pending after insert on public.student_enrollment_submissions
for each row execute function public.mark_student_enrollment_pending();

-- L'approbation élève exige deux fichiers réellement présents dans le bucket privé.
create or replace function public.admin_decide_student_registration(
  target_user_id uuid,
  decision text
) returns boolean language plpgsql security definer set search_path=public
as $$
declare dossier public.student_enrollment_submissions%rowtype;
begin
  if not public.is_admin() then raise exception 'Action réservée à un administrateur autorisé.'; end if;
  if decision not in ('approved','rejected') then raise exception 'Décision invalide.'; end if;
  if not exists(select 1 from public.profiles p where p.id=target_user_id and p.role='student'
    and p.registration_status='pending') then
    raise exception 'Inscription introuvable ou déjà traitée.';
  end if;
  select * into dossier from public.student_enrollment_submissions
    where user_id=target_user_id and status='pending' order by created_at desc limit 1 for update;
  if decision='approved' then
    if not found then raise exception 'Le dossier doit contenir la photo d’identité et la preuve de paiement.'; end if;
    if not exists(select 1 from storage.objects o where o.bucket_id='student-enrollment-documents' and o.name=dossier.identity_photo_path)
      or not exists(select 1 from storage.objects o where o.bucket_id='student-enrollment-documents' and o.name=dossier.payment_proof_path) then
      raise exception 'Une pièce du dossier est introuvable dans le stockage privé.';
    end if;
    update public.student_enrollment_submissions set status='approved',reviewed_by=auth.uid(),reviewed_at=now()
      where id=dossier.id;
  elsif found then
    update public.student_enrollment_submissions set status='rejected',reviewed_by=auth.uid(),reviewed_at=now()
      where id=dossier.id;
  end if;
  update public.profiles set registration_status=decision
    where id=target_user_id and role='student' and registration_status='pending';
  if not found then raise exception 'Le statut du profil élève n’a pas pu être mis à jour.'; end if;
  return true;
end; $$;
revoke all on function public.admin_decide_student_registration(uuid,text) from public;
grant execute on function public.admin_decide_student_registration(uuid,text) to authenticated;

commit;

-- Contrôles rapides (lecture seule).
select status,count(*) as dossiers from public.student_enrollment_submissions group by status order by status;
select id,email,full_name,series,registration_status from public.profiles where role='student' and registration_status<>'approved';
