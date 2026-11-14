-- AKADEMIA — Contrôles en lecture seule avant mise en ligne.
-- À exécuter dans Supabase SQL Editor avec un compte propriétaire du projet.
-- Ces requêtes ne modifient aucune donnée et n'affichent aucun mot de passe/secret.

-- 1) État du profil administrateur autorisé.
select
    u.email,
    (u.email_confirmed_at is not null) as email_confirme,
    u.last_sign_in_at,
    p.role,
    p.series,
    p.must_change_password,
    a.enabled as autorisation_admin_active
from auth.users u
left join public.profiles p on p.id = u.id
left join public.akademia_admin_allowlist a
    on a.email = lower(trim(coalesce(u.email, '')))
where lower(trim(coalesce(u.email, ''))) = 'julio7271@gmail.com';

-- 2) Activation RLS sur les tables qui portent des données personnelles ou des contenus payants.
select
    schemaname,
    tablename,
    rowsecurity as rls_active
from pg_tables
where schemaname = 'public'
  and tablename in (
      'profiles', 'subscriptions', 'student_messages', 'student_progress',
      'course_lesson_content', 'course_release_schedule', 'akademia_admin_allowlist'
  )
order by tablename;

-- 3) Politiques actives : vérifier qu'aucune politique permissive héritée ne contourne les règles attendues.
select
    schemaname,
    tablename,
    policyname,
    roles,
    cmd,
    qual,
    with_check
from pg_policies
where (schemaname = 'public' and tablename in (
          'profiles', 'subscriptions', 'student_messages', 'student_progress',
          'course_lesson_content', 'course_release_schedule', 'akademia_admin_allowlist'
      ))
   or (schemaname = 'storage' and tablename = 'objects')
order by schemaname, tablename, policyname;

-- 4) Configuration du bucket de preuves : il doit être privé et limité à 700 Ko.
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id = 'payment-proofs';

-- 5) Nombre de leçons et état du calendrier de publication.
select count(*) as nombre_de_lecons_protegees
from public.course_lesson_content;

select series, count(*) as dates_planifiees,
       count(*) filter (where release_at <= now()) as dates_deja_atteintes
from public.course_release_schedule
group by series
order by series;

-- 6) Détecter les demandes dont le fichier de preuve n'existe plus.
select s.id, s.user_id, s.status, s.created_at, s.proof_path
from public.subscriptions s
left join storage.objects o
  on o.bucket_id = 'payment-proofs' and o.name = s.proof_path
where o.id is null
order by s.created_at desc;
