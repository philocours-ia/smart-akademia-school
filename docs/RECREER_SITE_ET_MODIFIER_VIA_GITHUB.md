# Recréer Smart Akademia School et pouvoir le modifier facilement

Le site Netlify est l'hébergement/publication du projet ; ce n'est pas l'éditeur du code source. Pour modifier durablement l'application, conserver les fichiers dans un dépôt GitHub privé et relier ce dépôt à Netlify.

## 1. Préparer le dépôt GitHub

1. Télécharger l'archive `SMART_AKADEMIA_SCHOOL_DEPOT_GITHUB_NETLIFY.zip`.
2. Décompresser l'archive sur l'ordinateur.
3. Créer un nouveau dépôt GitHub **privé**, par exemple `smart-akademia-school`.
4. Ajouter à la racine du dépôt le contenu décompressé : les dossiers `site/`, `supabase/`, `docs/`, `data/`, ainsi que `README.md`, `.gitignore` et `netlify.toml`. Ne pas ajouter le dossier parent qui enveloppe ces fichiers.
5. Valider (commit) les fichiers.

Ne jamais ajouter de mot de passe, clé `service_role`, clé `sb_secret_`, secret de paiement ou fichier `.env` contenant des secrets. Le dépôt doit rester privé, même si la clé Supabase publishable est conçue pour être utilisée dans le navigateur.

## 2. Recréer le site Netlify

1. Se connecter à Netlify.
2. Choisir **Add new project** puis **Import an existing project** (ou le libellé équivalent).
3. Choisir GitHub, autoriser Netlify à accéder au dépôt privé, puis sélectionner `smart-akademia-school`.
4. Vérifier les paramètres détectés par `netlify.toml` :
   - Build command : laisser vide.
   - Publish directory : `site`.
5. Lancer le déploiement.

Le fichier `netlify.toml` inclus fixe déjà le répertoire de publication à `site`.

## 3. Modifier le site par la suite

1. Modifier les fichiers dans `site/` (ou confier la modification des sources à un développeur).
2. Envoyer les changements (commit puis push) dans le dépôt GitHub.
3. Netlify lance automatiquement un nouveau déploiement à partir des changements.
4. Vérifier le Deploy Preview ou le déploiement de production avant de communiquer la nouvelle version.

Il n'est donc pas nécessaire de supprimer le site pour chaque modification. Pour une modification importante, faire d'abord un aperçu (Deploy Preview) et conserver un historique des commits.

## 4. Après la recréation

- Noter la nouvelle URL `*.netlify.app`.
- Dans Supabase → Authentication → URL Configuration, remplacer le Site URL par la nouvelle URL et ajouter les URL de redirection nécessaires.
- Vérifier que le projet Supabase existant est toujours actif. La suppression du projet Netlify ne supprime pas, à elle seule, un projet Supabase distinct.
- Tester les connexions élève et administrateur, les redirections Auth, l'accès aux cours et les règles RLS.
- Ne pas rejouer les migrations déjà appliquées.

## 5. Déploiement manuel (solution provisoire)

Pour publier sans GitHub, décompresser aussi l'archive Netlify et déposer le contenu de `site/` sur Netlify Drop. Pour chaque mise à jour, déposer à nouveau les fichiers mis à jour sur le même site, depuis sa page Deploys. Cette méthode fonctionne, mais elle est moins adaptée aux modifications fréquentes et à l'historique des versions.
