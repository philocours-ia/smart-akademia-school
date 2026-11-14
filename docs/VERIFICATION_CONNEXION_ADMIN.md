# Vérification de la connexion administrateur — Smart Akademia School

## Ce que vérifie l'application

1. L'identifiant affiché doit être `akademia`. Il est mappé vers l'adresse Auth autorisée configurée dans `site/index.html`.
2. Le mot de passe est vérifié par Supabase Auth (`signInWithPassword`).
3. Le profil Supabase doit avoir `role = 'admin'`.
4. Si `must_change_password = true`, l'écran de changement s'affiche et le tableau de bord reste inaccessible.
5. Après mise à jour du mot de passe Auth, le trigger `auth.users` doit mettre `must_change_password` à `false`.
6. L'application appelle `rpc('is_admin')`; le serveur ne confirme le rôle admin que si le mot de passe initial a été changé.
7. Les actions et lectures de données restent contrôlées par les politiques RLS.

## Provisionnement du compte

- Adresse autorisée : `julio7271@gmail.com`.
- Identifiant de portail : `akademia`.
- Le mot de passe initial est défini ou réinitialisé uniquement dans Supabase Authentication → Users. Ne jamais l'ajouter au HTML, au SQL, à GitHub, à une archive de déploiement ou à un message.
- Le propriétaire doit confirmer l'adresse e-mail et vérifier `must_change_password = true` avant le premier essai.
- La première connexion doit remplacer le mot de passe initial par un mot de passe robuste d'au moins 12 caractères.

## Requête de contrôle en lecture seule

Exécuter dans Supabase SQL Editor :

```sql
select
  u.email,
  (u.email_confirmed_at is not null) as email_confirme,
  u.last_sign_in_at,
  p.role,
  p.series,
  p.must_change_password,
  a.enabled as adresse_admin_autorisee
from auth.users u
left join public.profiles p on p.id = u.id
left join public.akademia_admin_allowlist a
  on a.email = lower(trim(u.email))
where lower(u.email) = lower('julio7271@gmail.com');
```

Avant le premier accès, résultat attendu : `role = admin`, `series = Administrateur`, `must_change_password = true`, `adresse_admin_autorisee = true`, et adresse confirmée. Après changement du mot de passe : `must_change_password = false`.

## Scénarios à effectuer sur le domaine HTTPS

### Positifs

- Se connecter depuis le formulaire commun à la racine avec `akademia` et le mot de passe du compte Auth associé à l’adresse configurée. Tous les rôles utilisent le même bouton de connexion.
- Vérifier l'écran de première connexion, puis changer le mot de passe.
- Vérifier que le tableau de bord s'ouvre seulement après la confirmation serveur.

### Négatifs

- Un compte élève utilisé sur le portail admin doit être refusé et déconnecté.
- Un compte admin avec `must_change_password = true` ne doit pas ouvrir le tableau de bord.
- Si `rpc('is_admin')` ne renvoie pas `true`, le tableau de bord doit rester inaccessible.
- Depuis l'espace élève, aucun lien ou bouton d'accès admin ne doit être visible.

## État du test au 14 novembre 2026

La syntaxe JavaScript, le manifeste et les chemins des ressources PWA ont été vérifiés statiquement. Le profil administrateur a été signalé comme `admin` dans le projet lors des étapes précédentes. En revanche, aucune connexion Auth réelle, aucun changement de mot de passe et aucun contrôle RLS distant n'ont été réalisés depuis l'environnement de préparation. Le propriétaire doit effectuer ces essais lui-même ; il ne doit jamais transmettre son mot de passe.


## Diagnostic rapide

Exécuter `supabase/diagnostics/10_DIAGNOSTIC_CONNEXION_ADMIN.sql` dans le SQL Editor. Il indique si l'utilisateur Auth existe, si l'e-mail est confirmé, si le profil est admin et si un changement initial du mot de passe reste obligatoire. Il ne peut pas lire ni valider le mot de passe.

L'identifiant `akademia` est un alias, pas un utilisateur Supabase distinct. Dans cette version, il pointe vers `julio7271@gmail.com`. Si le compte Auth de l'administrateur utilise un autre e-mail, le propriétaire doit harmoniser cet e-mail dans le paramètre `SUPABASE_CONFIG.adminEmail` et dans `akademia_admin_allowlist`, sans publier de mot de passe.
