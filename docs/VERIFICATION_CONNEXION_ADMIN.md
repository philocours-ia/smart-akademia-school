# Vérification de la connexion administrateur — Smart Akademia School

## État du contrôle

Le contrôle du code local est terminé :
- les scripts JavaScript intégrés passent la vérification de syntaxe Node.js ;
- le manifeste PWA est un JSON valide ;
- l'écran d'administration utilise Supabase Auth (`signInWithPassword`) ;
- le profil doit posséder le rôle `admin` ;
- le changement du mot de passe initial est obligatoire ;
- juste avant l'ouverture du tableau de bord, l'application vérifie `rpc('is_admin')` ;
- en cas d'échec du contrôle administrateur, la session est fermée et le tableau de bord reste masqué.

**Le test réel du serveur Supabase n'est pas encore effectué.** Le fichier `index.html` contient encore les valeurs de configuration provisoires (`VOTRE-PROJET`, clé publique et e-mail admin). Aucun projet Supabase ni compte administrateur réel n'est connecté à ce paquet.

## Mise en service du compte admin

1. Exécuter `AKADEMIA_supabase_setup.sql` dans Supabase SQL Editor.
2. Dans `MIGRATION_CONNEXION_ADMIN.sql`, remplacer `VOTRE_ADRESSE_ADMIN` par l'adresse e-mail exacte. Exécuter ensuite la migration.
3. Après la migration, créer l'utilisateur correspondant dans Authentication → Users avec un mot de passe temporaire. La liste d'autorisation privée permet au trigger de créer directement un profil `admin`; aucune série élève factice ni métadonnée `role=admin` n'est utilisée.
4. Si le compte Auth existait déjà, la migration promeut le profil correspondant à l'adresse autorisée et impose le changement de mot de passe.
5. Dans `index.html`, remplacer `url`, `anonKey` et `adminEmail` dans `SUPABASE_CONFIG`. Utiliser seulement la clé publique `anon`/publishable. **Ne jamais utiliser ou publier la clé `service_role`/secret.**
6. Publier le site en HTTPS, puis ouvrir `/administration.html`.

## Scénario de test positif

- Identifiant : `akademia`.
- Mot de passe : celui défini pour l'utilisateur dans Supabase Auth.
- Premier accès : l'écran de changement de mot de passe doit apparaître.
- Après choix d'un mot de passe robuste d'au moins 12 caractères : l'application doit vérifier la mise à jour du hash dans Auth, confirmer `must_change_password = false`, vérifier `is_admin() = true`, puis ouvrir le tableau de bord.

## Scénarios de test négatif

- Un compte élève utilisé sur `/administration.html` ne doit pas ouvrir l'administration ; la session est fermée.
- Un compte administrateur avec `must_change_password = true` ne doit pas accéder aux données d'administration avant d'avoir changé son mot de passe.
- Si `is_admin()` ne renvoie pas `true`, le tableau de bord doit rester inaccessible.
- Sur la page élève, un compte admin ne doit pas être présenté comme un élève.

## Requête de diagnostic SQL

Remplacer l'adresse ci-dessous et exécuter la requête dans SQL Editor :

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
where lower(u.email) = lower('VOTRE_ADRESSE_ADMIN');
```

Résultat attendu après provisionnement : `role = admin`, `series = Administrateur`, `must_change_password = true`, `adresse_admin_autorisee = true`. Après le changement initial du mot de passe, `must_change_password` doit être `false`.

## Informations nécessaires pour un test réel accompagné

Il faut d'abord le Project URL Supabase, la clé publique anon/publishable et l'adresse e-mail du compte admin. L'administrateur saisira lui-même son mot de passe dans le portail ; il ne faut pas l'envoyer dans la conversation. Ne jamais communiquer la clé `service_role`/secret.
