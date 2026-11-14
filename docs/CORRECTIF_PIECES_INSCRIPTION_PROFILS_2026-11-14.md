# Correctif — pièces justificatives visibles avant inscription des profils professionnels

## Problème traité
Les champs des justificatifs des profils enseignant, promoteur et partenaire dépendaient d’un bloc HTML vide, alimenté ensuite par un rendu JavaScript dynamique. Ce correctif place désormais tous les groupes de champs dans le HTML et ne fait que les afficher/masquer selon le profil choisi. Les champs d’un autre profil sont désactivés pour ne pas bloquer la validation du formulaire.

## Champs visibles avant création du compte
- Enseignant : photo d’identité, preuve du diplôme et spécialité proposée.
- Promoteur : photo d’identité, preuve du diplôme et niveau de diplôme (Baccalauréat minimum).
- Partenaire : nom du représentant et du partenaire/organisme, paiement initial de 100 000 Ar, MVola 0385528349 ou Binance Pay 820751129, référence de transaction, preuve de paiement, référence FINANCEMENT.

Les fichiers sont encore contrôlés côté navigateur (type et taille), gardés temporairement dans IndexedDB pour les flux de confirmation e-mail, puis téléversés dans les buckets privés Supabase au moyen de la session de l’utilisateur. Ce correctif ne remplace pas les politiques RLS/Storage et ne valide aucun paiement automatiquement.

## Publication
Remplacer `site/index.html`, `site/role-portal.js` et `site/service-worker.js` dans le dépôt GitHub. Le script reçoit aussi un paramètre de version `?v=16-proof-fields` et le service worker passe en v16 pour forcer le renouvellement du cache. Le déploiement Netlify se fera selon la liaison GitHub existante.

Aucune nouvelle migration SQL n’est ajoutée. Les migrations précédentes et les buckets privés requis doivent déjà être présents. Les transferts réels et les permissions Storage doivent être testés sur le projet Supabase du propriétaire.
