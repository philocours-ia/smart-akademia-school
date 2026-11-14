-- Diagnostic en lecture seule de l'accès administrateur.
-- À exécuter dans Supabase SQL Editor (propriétaire du projet).
-- Ne modifie aucune donnée et n'affiche aucun secret ni mot de passe.
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
