-- SMART AKADEMIA SCHOOL — Diagnostic en lecture seule des comptes et espaces
-- À exécuter par le propriétaire dans Supabase SQL Editor.
-- Ce script ne modifie aucune donnée et ne crée aucune table/politique.

-- 1) Répartition des rôles réellement enregistrés.
select role, registration_status, count(*) as total
from public.profiles
group by role, registration_status
order by role, registration_status;

-- 2) Candidatures professionnelles et preuves initiales partenaires.
select
  a.id as application_id,
  a.user_id,
  a.application_type,
  a.status as application_status,
  a.applicant_name,
  a.applicant_email,
  a.organization_name,
  a.monthly_commitment_accepted,
  d->>'payment_method' as payment_method,
  d->>'payment_reference' as payment_reference,
  d->>'transaction_reference' as transaction_reference,
  d->>'amount_ar' as declared_amount_ar,
  d->>'path' as payment_proof_path,
  exists (
    select 1 from storage.objects o
    where o.bucket_id = 'partner-payment-proofs'
      and o.name = d->>'path'
  ) as payment_proof_exists_in_storage,
  a.created_at,
  a.reviewed_at,
  a.review_note
from public.role_applications a
left join lateral jsonb_array_elements(
  case when jsonb_typeof(a.documents) = 'array' then a.documents else '[]'::jsonb end
) d on d->>'kind' = 'payment_proof'
where a.application_type in ('partner','teacher','promoter')
order by a.created_at desc;

-- 3) Registre des cotisations partenaires et présence physique des preuves.
select
  c.id as contribution_id,
  c.user_id,
  p.email,
  p.full_name,
  c.amount_ar,
  c.payment_method,
  c.payment_reference,
  c.transaction_reference,
  c.status,
  c.proof_path,
  exists (
    select 1 from storage.objects o
    where o.bucket_id = 'partner-payment-proofs' and o.name = c.proof_path
  ) as proof_exists_in_storage,
  c.created_at,
  c.reviewed_at
from public.partner_contributions c
left join public.profiles p on p.id = c.user_id
order by c.created_at desc;

-- 4) Tickets et durée de validité des membres partenaires.
select
  m.user_id,
  p.email,
  p.full_name,
  p.role,
  m.access_ticket,
  m.ticket_valid_until,
  m.contribution_expires_at,
  (m.ticket_valid_until >= current_date and m.contribution_expires_at > now()) as membership_currently_active,
  m.updated_at
from public.partner_memberships m
left join public.profiles p on p.id = m.user_id
order by m.updated_at desc;

-- 5) État synthétique des enseignants et de leurs affectations.
select
  p.id as teacher_id,
  p.email,
  p.full_name,
  p.registration_status,
  count(a.id) filter (where a.active) as active_assignments
from public.profiles p
left join public.teacher_subject_assignments a on a.teacher_id = p.id
where p.role = 'teacher'
group by p.id, p.email, p.full_name, p.registration_status
order by p.full_name;

-- 6) État synthétique des promoteurs et commissions.
select
  p.id as promoter_id,
  p.email,
  p.full_name,
  p.referral_code,
  count(c.id) as approved_student_commissions,
  coalesce(sum(c.amount_ar), 0) as commissions_total_ar
from public.profiles p
left join public.promoter_commissions c on c.promoter_id = p.id
where p.role = 'promoter'
group by p.id, p.email, p.full_name, p.referral_code
order by p.full_name;

-- 7) Configuration des buckets utilisés par les espaces professionnels.
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id in ('partner-payment-proofs','role-application-documents','teacher-course-files')
order by id;
