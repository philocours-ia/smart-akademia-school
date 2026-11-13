# Smart Akademia School — dépôt source

Ce dépôt réunit la version de référence de l'application, les scripts Supabase et les ressources pédagogiques.

## Arborescence

- `site/` : fichiers web statiques à publier sur Netlify.
- `supabase/01_AKADEMIA_supabase_setup.sql` : **script principal unique** pour initialiser un nouveau projet Supabase.
- `supabase/migrations/02_MIGRATION_CONNEXION_ADMIN.sql` : à exécuter après le script principal, avec l’adresse administrateur déjà renseignée `julio7271@gmail.com`.
- `docs/` : guides et référentiel de sources.
- `data/` : exports de la banque Boky Citation.

## Mise en route sur un nouveau projet Supabase

1. Créer le projet Supabase.
2. Dans SQL Editor, exécuter une seule fois `supabase/01_AKADEMIA_supabase_setup.sql`.
3. Exécuter `supabase/migrations/02_MIGRATION_CONNEXION_ADMIN.sql` après le script principal. L’adresse `julio7271@gmail.com` est déjà inscrite dans la liste d’autorisation.
4. Créer ensuite l'utilisateur administrateur dans Supabase Auth avec cette adresse.
5. La configuration `SUPABASE_CONFIG` du `site/index.html` est déjà renseignée pour ce projet avec l’URL, la clé publishable et l’adresse `julio7271@gmail.com`. Ne jamais placer une clé `service_role`/`secret` ou un mot de passe dans le dépôt ou le code web.
6. Déployer le contenu de `site/` sur Netlify. Pour un dépôt Git connecté à Netlify, définir `site` comme répertoire de publication et ne définir aucune commande de build.

## Important : ne pas mélanger les anciennes migrations

Le script principal `01_AKADEMIA_supabase_setup.sql` est la version consolidée actuelle. Il inclut déjà les classes/séries Seconde, Première L/S/OSE et Terminale L/S/OSE, ainsi que les protections de profil et les règles de cohérence série-abonnement/messages.

Les anciens fichiers `MIGRATION_CLASSE_SECONDE.sql` et `MIGRATION_T11_PROGRAMMES_ET_SERIES.sql` ne sont volontairement pas inclus : ils servaient à faire évoluer une ancienne base et leurs déclencheurs d'inscription peuvent remplacer la logique de création sécurisée du compte administrateur. Ne pas les exécuter sur cette installation neuve.

Le script `02_MIGRATION_CONNEXION_ADMIN.sql` doit impérativement être exécuté après le script principal. Il met en place la liste privée des e-mails autorisés et modifie le déclencheur Auth afin qu'un compte admin soit reconnu sans devoir déclarer une série scolaire.

## Dépôt et données sensibles

Conserver le dépôt privé pendant la configuration. La clé publique Supabase peut être utilisée côté navigateur, mais aucune clé secrète/service_role, aucun mot de passe et aucun justificatif de paiement ne doivent être commités.

> Pour une base Supabase déjà existante contenant des données, ne pas relancer le script principal sans sauvegarde et revue de migration. Ce paquet décrit la mise en place sur un nouveau projet.


## Configuration Supabase déjà renseignée

Le fichier `site/index.html` contient le Project URL, la clé **publishable** publique et l'adresse e-mail d'administration communiqués pour ce projet. La clé publishable est destinée au navigateur. Ne jamais ajouter de clé `sb_secret_`, `service_role`, mot de passe de base de données ou autre secret dans ce dépôt. Vérifier les politiques RLS et les autorisations avant toute ouverture aux élèves.

Compte administrateur autorisé par la migration : `julio7271@gmail.com` (identifiant de connexion affiché : `akademia`). Le compte Auth doit encore être créé/vérifié dans Supabase Authentication.
