# Vérification fonctionnelle de recette par rôle

## Statut de cette recette

**Recette réelle non exécutée ici.** Cette tâche n'a pas accès au projet Supabase du propriétaire, à des identifiants par rôle, aux secrets MVola ni à un navigateur connecté au site Netlify. Les tests ci-dessous sont une procédure reproductible à exécuter sur un environnement de recette. Ne pas inscrire d'élèves réels, ne pas téléverser de documents personnels de production et ne pas lancer de paiements réels.

La revue de code a repéré et corrigé dans `site/portal-resilience.js` un contrôle de disponibilité qui ne tenait compte que de `window.supabaseClient`. Le code historique peut définir `supabaseClient` comme variable lexicale globale, non exposée sur `window`; le contrôle utilise désormais le binding lexical lorsqu'il existe.

## Préparation

- Déployer la branche de recette sur un domaine de test HTTPS.
- Utiliser un projet Supabase de recette avec les migrations applicatives requises effectivement appliquées. La présence des fichiers SQL dans Git ne prouve pas qu'ils sont appliqués.
- Créer des comptes Auth distincts pour élève en attente, élève approuvé sans abonnement, élève abonné, candidat enseignant, candidat partenaire, candidat promoteur, enseignant approuvé, partenaire actif, promoteur approuvé et administrateur.
- Fournir des données de test minimales : affectation enseignant, journée de travail, ressource, candidature, contribution partenaire, filleul validé, message, cours et date de publication selon les cas.
- Vérifier les variables Supabase du site et la configuration URL de connexion/callback. Utiliser uniquement des fichiers fictifs et comptes Sandbox.
- Après déploiement, ouvrir la PWA en ligne, confirmer le cache `smart-akademia-school-shell-v19-portal-resilience` via DevTools → Application → Service Workers, puis recharger. Consulter Console et Network.

## Parcours et critères d'acceptation

### 1. Élève en attente / refusé

1. Se connecter avec le compte en attente : l'écran « Validation de l’inscription » s'affiche et la zone de dépôt est présente.
2. Envoyer photo et reçu fictifs avec une référence valide : les deux fichiers sont chargés dans le bucket privé et un dossier apparaît en attente.
3. Vérifier l'accès Storage : l'élève ne lit que ses fichiers ; un autre compte élève ne les lit pas.
4. Refuser le dossier depuis l'admin : le portail doit montrer le refus et permettre une nouvelle soumission sans créer un autre compte.
5. Simuler l'absence de migration ou une panne Storage : le portail présente un diagnostic lisible, pas un écran de chargement infini.

### 2. Élève approuvé sans abonnement puis élève abonné

1. Se connecter : l'élève approuvé arrive dans l'application principale, avec nom/série et état d'abonnement.
2. Sans abonnement valide, essayer un cours protégé : la base/RLS doit refuser le contenu ; les sections publiques de citations et bibliothèque restent affichables.
3. Avec un abonnement actif non expiré : vérifier progression, accès aux leçons publiées, badge et ticket.
4. Envoyer une demande d'abonnement en Sandbox ou utiliser le parcours manuel de recette : statut pending avant validation, ticket et accès après décision autorisée.
5. Tester formule mensuelle et annuelle ; l'annuel doit exiger une date de fin réelle valide, jamais une date arbitraire.
6. Vérifier citations, recherche/filtres, bibliothèque, exercices, forum, navigation mobile et messages. Les données qui dépendent de Supabase doivent montrer une réponse vide explicite ou une erreur exploitable.

### 3. Candidat enseignant

1. Ouvrir la candidature enseignant et confirmer la présence du texte de cotisation 5 000 Ar et des boutons radio « J’accepte » / « Je refuse ».
2. Soumettre sans choix, puis avec refus : la création du compte doit être bloquée ; aucun utilisateur Auth ne doit être créé.
3. Accepter et joindre fichiers fictifs valides : poursuivre l'inscription ; confirmer les pièces en IndexedDB puis dans Storage privé après authentification.
4. Ouvrir le portail candidat : spécialité, diplôme et statut doivent être visibles.
5. Tester approbation sans justificatif ou sans affectation : action rejetée avec un message clair. Avec pièces et affectation valides : rôle enseignant et affectation visibles au prochain rafraîchissement.

### 4. Candidat partenaire

1. Créer le compte candidat partenaire avec organisme, référence et justificatif fictifs.
2. Confirmer le transfert de preuve vers `partner-payment-proofs`; vérifier qu'un utilisateur non propriétaire ne peut pas la lire.
3. Vérifier l'affichage du statut de candidature et, après approbation, de la ligne de cotisation initiale en attente (migration 10 requise).
4. Refuser/valider la cotisation, contrôler l'historique, ticket et dates ; l'accès cours reste bloqué avant activation et ouvert dans les bornes attendues après.
5. Panne d'un des trois blocs : les autres blocs restent visibles et le diagnostic nomme la donnée indisponible.

### 5. Candidat promoteur puis promoteur approuvé

1. Déposer une candidature fictive avec pièce d'identité/diplôme ; vérifier statut et note.
2. Après approbation, vérifier l'attribution du code de huit caractères et l'ouverture du portail promoteur.
3. Vérifier code/lien, filleuls validés, commissions, solde, historique financier et messagerie.
4. Avec solde inférieur à 30 000 Ar, bouton de demande inactif ; au-dessus, demande possible et visible dans l'administration.
5. Simuler séparément l'échec de chaque requête (commissions, finance, RPC des filleuls) : les panneaux indépendants doivent rester rendus, afficher l'erreur concernée et ne pas proposer un paiement lorsque le solde ne peut être confirmé.

### 6. Enseignant approuvé

1. Vérifier affectations, jours validés, calcul au tarif de 6 000 Ar/jour et solde net des demandes en attente/approuvées.
2. Envoyer demande salaire/avance ; la demande doit apparaître dans les deux espaces selon les droits.
3. Tester congé, remplacement et démission avec dates/champs invalides puis valides.
4. Déposer ressource PDF/DOC fictive dans les séries affectées ; elle reste non publiée avant décision admin.
5. Vérifier suivi uniquement des séries affectées, agenda filtré, messages et état des erreurs partielles.

### 7. Administrateur

1. Utiliser un compte admin dédié dont le mot de passe initial a été changé ; un compte non-admin ne doit pas voir/faire les actions privilégiées.
2. Vérifier boîte de validation : dossiers élèves, candidatures, cotisations et liens signés temporaires.
3. Vérifier supervision RPC, inscriptions, abonnements, ressources, affectations, paiements/finances, demandes de personnel, promoteurs et messagerie.
4. Tenter chaque action avec décision invalide, dossier incomplet ou date manquante : l'action doit échouer sans changement d'état.
5. Après décision valide, recharger : statut, ticket et carte correspondante doivent refléter la base.

## Fiche de résultat à compléter pendant la recette

| Rôle/parcours | Résultat (OK/KO/Non exécuté) | Erreur console/API | Migration/RLS à vérifier |
|---|---|---|---|
| Élève en attente/refusé | Non exécuté | — | — |
| Élève approuvé sans abonnement | Non exécuté | — | — |
| Élève abonné | Non exécuté | — | — |
| Candidat enseignant | Non exécuté | — | — |
| Candidat partenaire | Non exécuté | — | — |
| Candidat promoteur | Non exécuté | — | — |
| Enseignant approuvé | Non exécuté | — | — |
| Partenaire actif | Non exécuté | — | — |
| Promoteur approuvé | Non exécuté | — | — |
| Administrateur | Non exécuté | — | — |

**Ne considérer les portails comme validés qu'après exécution des parcours en environnement de recette avec captures des résultats et journaux nettoyés de tout secret ou donnée personnelle.**
