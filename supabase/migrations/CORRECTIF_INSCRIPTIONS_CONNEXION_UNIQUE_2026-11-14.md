# Smart Akademia School — correctif des inscriptions et de la connexion unique

Date : 14 novembre 2026

## Ce qui change dans l'application

1. Un seul formulaire de connexion et un seul bouton « Se connecter » sont utilisés par l'administration, les élèves, les enseignants, les partenaires et les promoteurs.
2. Les utilisateurs ordinaires saisissent leur adresse e-mail. L'administrateur peut saisir l'alias `akademia`, qui est converti en l'adresse Auth définie dans `SUPABASE_CONFIG.adminEmail` (actuellement `julio7271@gmail.com`). Supabase Auth vérifie le mot de passe ; le rôle lu dans `public.profiles`, puis la RPC `is_admin()`, déterminent les droits effectifs.
3. Le formulaire élève exige avant l'appel `signUp` : photo d'identité, preuve du droit annuel MVola de 2 000 Ar et référence de transaction `AKADEMIA_DROIT`.
4. Le formulaire enseignant et promoteur exige avant `signUp` : photo d'identité et justificatif du diplôme. Le niveau minimal du promoteur reste le Baccalauréat.
5. Le formulaire partenaire exige avant `signUp` : preuve du premier versement de 100 000 Ar, mode MVola ou Binance Pay, identifiant de transaction et référence `FINANCEMENT`.
6. Après création du compte Auth, les fichiers sont envoyés vers les buckets privés Supabase. Si la confirmation e-mail retarde l'ouverture d'une session, les fichiers sont temporairement conservés dans IndexedDB sur le même navigateur, puis envoyés après la première connexion.

## Important à propos du stockage temporaire

IndexedDB est un stockage local du navigateur, pas un coffre chiffré fourni par l'application. Les utilisateurs doivent utiliser un appareil personnel et éviter les appareils partagés. Ils doivent rester sur le même navigateur jusqu'au transfert des pièces. Si le stockage du navigateur est effacé ou si l'utilisateur change d'appareil, il doit joindre à nouveau les pièces depuis son dossier en attente. Après transfert réussi et finalisation du dossier, les blobs temporaires sont supprimés.

## Mise à jour Supabase

Le projet de l'utilisateur avait déjà validé les migrations 01 à 09. Dans ce cas, exécuter uniquement, après sauvegarde et si elle n'est pas déjà appliquée :

`supabase/migrations/10_PREUVES_AVANT_INSCRIPTION_ET_PARTENAIRE.sql`

Cette migration permet l'upload du justificatif partenaire quand le profil est encore candidat et impose à l'approbation de la candidature que le justificatif privé, le mode, la référence de transaction, le montant et la référence de paiement soient cohérents. Après approbation de la candidature, une contribution est créée en attente ; le paiement reste à valider manuellement par l'administrateur. Ne pas rejouer les migrations 01 à 09.

## Diagnostic de la connexion administrateur

L'alias `akademia` est un alias de connexion, pas un compte Supabase indépendant. La configuration livrée le mappe vers `julio7271@gmail.com`. Cette adresse doit être identique à celle du compte créé dans Supabase Authentication et à celle activée dans `public.akademia_admin_allowlist`.

Si la connexion échoue, exécuter dans Supabase SQL Editor le script en lecture seule :

`supabase/diagnostics/10_DIAGNOSTIC_CONNEXION_ADMIN.sql`

Interprétation :

- `AUTH_USER_ABSENT` : l'utilisateur n'existe pas dans Supabase Auth ; le propriétaire doit le provisionner.
- `EMAIL_NON_CONFIRME` : confirmer l'adresse e-mail dans Supabase Auth.
- `PROFIL_ABSENT` : le profil lié au compte Auth est manquant ; examiner le trigger Auth avec le propriétaire.
- `ROLE_INCORRECT` : corriger l'allowlist/profil côté propriétaire après vérification d'identité.
- `PREMIERE_CONNEXION` : le compte doit changer son mot de passe depuis le formulaire commun.
- `COMPTE_ADMIN_CONFIGURE` : le compte est provisionné selon les éléments vérifiés par le diagnostic ; cela ne prouve pas que le mot de passe saisi est correct.

Ne jamais transmettre le mot de passe, une clé `service_role`, une clé secrète ou un accès propriétaire à l'assistant. Le diagnostic ne lit ni ne valide le mot de passe.

## Publication via GitHub et Netlify

1. Décompresser l'archive source et remplacer les fichiers du dépôt GitHub par cette version, en conservant le dépôt privé.
2. Pousser le commit sur la branche reliée à Netlify.
3. Vérifier dans Netlify que le répertoire publié reste `site` et que la commande de build reste vide.
4. Attendre un déploiement Netlify réussi ; aucun déploiement n'est réalisé par la création de ces fichiers.
5. Recharger le site en forçant l'actualisation. Le service worker a été incrémenté vers `v13-single-login-preregister-proofs` afin de supprimer les anciens caches applicatifs.
6. Ne tester l'authentification que sur le domaine HTTPS réel, puis vérifier dans Supabase Authentication → URL Configuration que le `Site URL` et les redirections correspondent à ce domaine.

## Contrôles réalisés localement

- Syntaxe JavaScript : 3 scripts inline, `role-portal.js` et `service-worker.js` validés avec `node --check`.
- Aucun identifiant HTML dupliqué.
- Aucun chemin local `src`/`href` manquant dans `index.html`.
- Tous les éléments de l'App Shell PWA référencés existent.
- Manifeste PWA JSON valide.
- Un seul formulaire de connexion, un seul bouton de soumission de connexion.
- Les champs de pièces et de référence sont obligatoires dans les formulaires initiaux.

## Limites des tests

Aucune connexion réelle à Supabase, aucune exécution de la migration 10 sur le projet distant et aucun déploiement Netlify n'ont été réalisés depuis l'environnement de préparation. L'upload Storage, les politiques RLS et le mot de passe Auth doivent être testés par le propriétaire sur son projet.
