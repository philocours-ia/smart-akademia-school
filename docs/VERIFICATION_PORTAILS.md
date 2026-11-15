# Vérification des portails — branche de travail

## Revue statique effectuée

Les portails sont rendus depuis `site/role-portal.js` dans `renderRolePortal()` et séparés par rôle : élève en attente, candidat (`applicant`), enseignant, partenaire et promoteur. L’administration est rendue dans `site/index.html` puis alimentée par les opérations administratives du même module. Le contenu métier (dossiers, affectations, cotisations, commissions, cours et tickets) vient de Supabase ; sa présence dans le HTML ne garantit pas que les données du projet distant soient configurées.

### Vérifications du code

- **Élève en attente :** le dossier et son statut sont lus depuis `student_enrollment_submissions`; le dépôt téléverse les pièces dans le bucket privé avant l’insertion. L’accès principal élève ne s’ouvre qu’après approbation.
- **Candidat :** le dossier `role_applications` est consulté et son état/avis sont affichés. L’inscription initiale garde les justificatifs dans IndexedDB jusqu’à ce que l’utilisateur puisse ouvrir une session.
- **Enseignant :** affectations, jours de travail, finance, demandes de personnel, ressources, progression et agenda sont chargés indépendamment. Les erreurs sont regroupées afin de préserver les rubriques disponibles.
- **Partenaire :** adhésion, cotisations et candidature sont chargées séparément. Les preuves consultées par l’administration utilisent des URL Storage signées temporaires. La première cotisation exige la migration 10 pour être automatiquement reliée après validation de la candidature.
- **Promoteur :** le code source précédent interrompait l’affichage complet si l’une des requêtes commissions, finance ou filleuls échouait. `site/portal-resilience.js` remplace ce rendu par des rubriques indépendantes, montre les erreurs de chaque panneau sans masquer les autres, et désactive la demande de paiement si les données nécessaires n’ont pas été lues.
- **Administration :** les listes sont alimentées par des RPC ou tables protégées, et la supervision appelle `get_akademia_admin_supervision()` définie dans la migration 09. La décision côté navigateur ne remplace pas la vérification admin/RLS côté base.

## Limites du contrôle

C’est une revue statique des sources de cette branche. Aucun accès à l’instance Supabase réelle, aucun compte de test par rôle et aucun navigateur connecté au site publié ne sont disponibles ici. Les vérifications live suivantes restent à effectuer : déploiement, console navigateur, authentification pour chaque rôle, migrations exactes effectivement appliquées, politiques RLS, existence des buckets privés, données réelles et parcours lecture/écriture.

## Déploiement et recette

Le service worker est passé en cache v19 et injecte le module de résilience après les scripts applicatifs. Après le push sur la branche reliée à Netlify, attendre le déploiement puis fermer/réouvrir la PWA ou faire un rechargement forcé pour installer le nouveau shell.

Tester avec des comptes séparés :

1. Élève en attente, élève approuvé sans abonnement, puis élève abonné : dossier, refus/reprise, cours, progression, citations, bibliothèque, exercices, forum et messages.
2. Candidat enseignant/partenaire/promoteur : afficher les pièces, soumettre le dossier, rafraîchir le statut ; vérifier les politiques Storage et RLS.
3. Enseignant : affectations, journées, solde, demandes, agenda, ressources et messages ; vérifier la progression des élèves selon les séries attribuées.
4. Partenaire : candidature initiale, cotisation, historique, statut du ticket, lien signé et consultation de cours uniquement après activation.
5. Promoteur : code/lien, filleuls, commissions, finance et messages ; simuler une requête/table indisponible et confirmer que les autres cartes restent visibles.
6. Administrateur : boîte de validation, statistiques, supervision, abonnement, inscriptions, cotisations, affectations, staff, paie, messages et ressources ; vérifier qu’un compte non-admin reçoit un refus du serveur.

Ne pas utiliser les comptes ou données réelles de production pour une recette destructive.
