# Smart Akademia School — dépôt source

Ce dépôt réunit la version de référence de l'application, les scripts Supabase et les ressources pédagogiques.

## Arborescence

- `site/` : fichiers web statiques à publier sur Netlify.
- `supabase/01_AKADEMIA_supabase_setup.sql` : **script principal unique** pour initialiser un nouveau projet Supabase.
- `supabase/migrations/02_MIGRATION_CONNEXION_ADMIN.sql` : à exécuter après le script principal, après remplacement de `VOTRE_ADRESSE_ADMIN` par l'adresse e-mail réelle.
- `docs/` : guides et référentiel de sources.
- `data/` : exports de la banque Boky Citation.

## Mise en route sur un nouveau projet Supabase

1. Créer le projet Supabase.
2. Dans SQL Editor, exécuter une seule fois `supabase/01_AKADEMIA_supabase_setup.sql`.
3. Ouvrir `supabase/migrations/02_MIGRATION_CONNEXION_ADMIN.sql`, remplacer `VOTRE_ADRESSE_ADMIN` par l'adresse exacte du compte administrateur, puis exécuter le script.
4. Créer ensuite l'utilisateur administrateur dans Supabase Auth avec cette adresse.
5. Renseigner dans `site/index.html` l'URL Supabase, la clé publique `anon`/`publishable` et l'adresse e-mail administrateur. Ne jamais placer une clé `service_role`/`secret` ou un mot de passe dans le dépôt ou le code web.
6. Déployer le contenu de `site/` sur Netlify. Pour un dépôt Git connecté à Netlify, définir `site` comme répertoire de publication et ne définir aucune commande de build.

## Important : ne pas mélanger les anciennes migrations

Le script principal `01_AKADEMIA_supabase_setup.sql` est la version consolidée actuelle. Il inclut déjà les classes/séries Seconde, Première L/S/OSE et Terminale L/S/OSE, ainsi que les protections de profil et les règles de cohérence série-abonnement/messages.

Les anciens fichiers `MIGRATION_CLASSE_SECONDE.sql` et `MIGRATION_T11_PROGRAMMES_ET_SERIES.sql` ne sont volontairement pas inclus : ils servaient à faire évoluer une ancienne base et leurs déclencheurs d'inscription peuvent remplacer la logique de création sécurisée du compte administrateur. Ne pas les exécuter sur cette installation neuve.

Le script `02_MIGRATION_CONNEXION_ADMIN.sql` doit impérativement être exécuté après le script principal. Il met en place la liste privée des e-mails autorisés et modifie le déclencheur Auth afin qu'un compte admin soit reconnu sans devoir déclarer une série scolaire.

## Dépôt et données sensibles

Conserver le dépôt privé pendant la configuration. La clé publique Supabase peut être utilisée côté navigateur, mais aucune clé secrète/service_role, aucun mot de passe et aucun justificatif de paiement ne doivent être commités.

> Pour une base Supabase déjà existante contenant des données, ne pas relancer le script principal sans sauvegarde et revue de migration. Ce paquet décrit la mise en place sur un nouveau projet.
