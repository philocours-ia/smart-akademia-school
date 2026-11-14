-- SMART AKADEMIA SCHOOL — Migration 09
-- Centre de supervision réservé à l'administration et affichage sécurisé
-- des enseignants affectés à la Philosophie pour la série de l'élève connecté.
-- Prérequis : migrations 01 à 08 déjà exécutées.
-- Exécuter une seule fois après sauvegarde.

begin;

-- 1) Vue synthétique des indicateurs opérationnels.
-- Les montants ne représentent que les paiements marqués comme validés dans la base.
-- Aucun paiement réel n'est exécuté par cette fonction.
create or replace function public.get_akademia_admin_supervision()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  month_start timestamptz := date_trunc('month', now());
begin
  if not public.is_admin() then
    raise exception 'Accès réservé à l’administration Smart Akademia School.';
  end if;

  select jsonb_build_object(
    'students_total', (select count(*) from public.profiles p where p.role='student'),
    'students_approved', (select count(*) from public.profiles p where p.role='student' and p.registration_status='approved'),
    'students_pending', (select count(*) from public.profiles p where p.role='student' and p.registration_status='pending'),
    'students_rejected', (select count(*) from public.profiles p where p.role='student' and p.registration_status='rejected'),
    'active_subscriptions', (select count(*) from public.subscriptions s where s.status='actif' and s.expires_at>now()),
    'expired_subscriptions', (select count(*) from public.subscriptions s where s.status='actif' and s.expires_at<=now()),
    'subscription_payments_pending', (select count(*) from public.subscriptions s where s.status='en_attente'),
    'enrollment_payments_pending', (select count(*) from public.student_enrollment_submissions e where e.status='pending'),
    'partner_contributions_pending', (select count(*) from public.partner_contributions c where c.status='pending'),
    'teachers_approved', (select count(*) from public.profiles p where p.role='teacher' and p.registration_status='approved'),
    'partners_approved', (select count(*) from public.profiles p where p.role='partner' and p.registration_status='approved'),
    'promoters_approved', (select count(*) from public.profiles p where p.role='promoter' and p.registration_status='approved'),
    'professional_applications_pending', (select count(*) from public.role_applications a where a.status='pending'),
    'finance_requests_pending', (select count(*) from public.finance_requests f where f.status='pending'),
    'staff_requests_pending', (select count(*) from public.staff_requests r where r.status='pending'),
    'completed_lessons_total', (select count(*) from public.student_progress sp where sp.completed=true),
    'monthly_confirmed_amount_ar', (
      coalesce((select sum(s.amount_ar) from public.subscriptions s
        where s.status='actif' and s.activated_at>=month_start),0)
      + coalesce((select sum(e.amount_ar) from public.student_enrollment_submissions e
        where e.status='approved' and e.reviewed_at>=month_start),0)
      + coalesce((select sum(c.amount_ar) from public.partner_contributions c
        where c.status='approved' and c.reviewed_at>=month_start),0)
    ),
    'students_by_series', coalesce((
      select jsonb_object_agg(x.series_name, x.total)
      from (
        select coalesce(nullif(trim(p.series),''),'Non renseignée') as series_name, count(*) as total
        from public.profiles p where p.role='student'
        group by coalesce(nullif(trim(p.series),''),'Non renseignée')
      ) x
    ), '{}'::jsonb),
    'updated_at', now()
  ) into payload;

  return payload;
end;
$$;
revoke all on function public.get_akademia_admin_supervision() from public, anon;
grant execute on function public.get_akademia_admin_supervision() to authenticated;

-- 2) Liste des enseignants officiellement affectés à la Philosophie pour
-- la série du compte élève courant. Le nom provient de profiles, la matière
-- et les séries proviennent de teacher_subject_assignments.
-- Aucun email ou renseignement privé n'est renvoyé.
create or replace function public.get_my_course_teachers(p_subject_name text default 'Philosophie')
returns table (
  teacher_name text,
  subject_name text,
  target_series text[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  caller_status text;
  caller_series text;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;

  select p.role, p.registration_status, p.series
    into caller_role, caller_status, caller_series
  from public.profiles p
  where p.id=auth.uid();

  if coalesce(caller_role,'') <> 'student' or coalesce(caller_status,'') <> 'approved' then
    return;
  end if;
  if lower(trim(coalesce(p_subject_name,'Philosophie'))) <> 'philosophie' then
    return;
  end if;

  return query
    select coalesce(nullif(trim(t.full_name),''),'Enseignant affecté')::text,
           a.subject_name,
           a.target_series
    from public.teacher_subject_assignments a
    join public.profiles t on t.id=a.teacher_id
    where a.active=true
      and lower(trim(a.subject_name))='philosophie'
      and caller_series=any(a.target_series)
      and t.role='teacher'
      and t.registration_status='approved'
    order by t.full_name asc;
end;
$$;
revoke all on function public.get_my_course_teachers(text) from public, anon;
grant execute on function public.get_my_course_teachers(text) to authenticated;

commit;

-- Contrôle manuel (lecture seule) :
-- select public.get_akademia_admin_supervision(); -- réservé admin
-- select * from public.get_my_course_teachers('Philosophie'); -- élève approuvé
