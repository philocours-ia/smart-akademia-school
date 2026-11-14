# Smart Akademia School — sources

Cette version contient le correctif de la boîte de validation administrative.

## Déploiement Netlify depuis GitHub

- Le dépôt comprend `netlify.toml` à sa racine.
- Répertoire de publication attendu : `site`.
- Base directory et commande de build : laisser vides.
- Chaque push sur la branche reliée à Netlify déclenche un nouveau déploiement.

## Boîte de validation administrative

Après connexion avec un compte administrateur reconnu par Supabase, le tableau de bord commence maintenant par une boîte regroupant :

1. Les dossiers d'inscription des élèves.
2. Les candidatures professionnelles (enseignants, partenaires, promoteurs).
3. Les cotisations partenaires à examiner.

Les dossiers élèves et candidatures affichent les données enregistrées et des liens signés temporaires vers leurs pièces privées. Les validations sont toujours exécutées par les fonctions RPC protégées de Supabase. Une pièce privée non consultable bloque l'approbation dans l'interface et doit faire l'objet d'une vérification Storage/RLS.

## Migrations

Ce correctif ne demande pas de nouvelle migration SQL. Il utilise les tables et fonctions déjà présentes dans les migrations 05, 06, 07 et 10 (ainsi que les fonctions administrateur définies précédemment). Si une requête affiche une erreur RLS ou une table absente, corriger la configuration Supabase existante avant toute décision.

## Fichiers principaux

- `site/index.html` : tableau de bord, boîte de validation, dossiers élèves.
- `site/role-portal.js` : candidatures professionnelles, cotisations et actions admin.
- `site/service-worker.js` : cache PWA v14 pour charger la nouvelle interface.
- `supabase/` : migrations historiques, non modifiées par ce correctif.

## Contrôles locaux réalisés

- Vérification syntaxique de `role-portal.js` et des scripts intégrés à `index.html`.
- Vérification des identifiants HTML uniques.
- Vérification du DOM : conteneurs de validation présents dans `view-admin`.
- Vérification du manifeste et de la structure de publication inchangés.

Les tests de connexion, RLS et Storage réels doivent être exécutés sur le projet Supabase du propriétaire.

## Correctif du portail partenaire (v15)

Consulter `docs/CORRECTIF_ESPACES_PARTENAIRES_ET_DIAGNOSTIC_PORTAILS_2026-11-14.md`. Il n'ajoute pas de migration SQL ; il rend le portail partenaire tolérant aux erreurs partielles et affiche les diagnostics des autres portails.


## Correctif des pièces justificatives à l'inscription (v16)

Les groupes de champs requis des candidatures enseignant, promoteur et partenaire sont maintenant directement présents dans `site/index.html`, puis affichés selon le profil choisi. Le service worker est en v16 et le script `role-portal.js` est versionné pour éviter de réutiliser l'ancien fichier en cache. Voir `docs/CORRECTIF_PIECES_INSCRIPTION_PROFILS_2026-11-14.md`.


## Correctif des formulaires d'inscription professionnels (v16)

Les pièces justificatives ne dépendent plus d'un bloc vide généré uniquement à l'exécution. Les champs des profils enseignant, promoteur et partenaire sont maintenant présents dans `site/index.html`; `role-portal.js` affiche le groupe adapté au profil choisi et désactive les champs des autres profils. La validation vérifie la présence des pièces avant l'appel à Supabase Auth. Le service worker passe en cache v16 et le script est chargé avec `?v=16-proof-fields`. Aucune migration SQL supplémentaire n'est requise. Voir `docs/CORRECTIF_PIECES_INSCRIPTION_PROFILS_2026-11-14.md`.
