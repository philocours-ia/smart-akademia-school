# Smart Akademia School — nouvelle livraison de fonctionnalités

**Date de préparation : 14 novembre 2026**  
**État : fichiers préparés, pas de mise en production ni d'exécution SQL distante déclarée.**

Ce document décrit les nouveautés comprises dans les migrations 06 à 09 et dans `site/index.html` / `site/role-portal.js`.

## Modules préparés

| Module | Parcours ajouté | Contrôle serveur prévu |
|---|---|---|
| Inscription élève | Dépôt photo d'identité, preuve MVola et identifiant de transaction pour le droit annuel de 2 000 Ar | RLS, stockage privé, contrôle d'existence des deux fichiers et décision admin par RPC |
| Candidature enseignant | Profil candidat, spécialité, diplôme et pièces | Rôle `applicant` avant décision ; approbation atomique avec affectation matière/séries |
| Candidature partenaire | Nom/organisme, acceptation de la contribution mensuelle | Rôle `applicant`, acceptation requise, validation administrative séparée de la preuve financière |
| Candidature promoteur | Niveau Bac minimum, photo et preuve du diplôme | Attribution du rôle promoteur et du code de huit caractères après validation |
| Cotisation partenaire | 100 000 Ar/mois, référence `FINANCEMENT`, preuve et transaction | Bucket privé, RPC admin, ticket à six chiffres et échéance annuelle saisie par la direction |
| Parrainage | Lien `?ref=XXXXXXXX`, suivi des élèves validés | Commission de 1 000 Ar créée côté base à l'approbation de l'inscription élève |
| Finance enseignant | 6 000 Ar par journée enregistrée, demande salaire/avance | Les jours sont enregistrés par admin ; RPC calcule le solde et impose 30 000 Ar minimum pour avance |
| Finance promoteur | Réclamation du solde de commissions | RPC impose le seuil de 30 000 Ar |
| Demandes personnel | Congé, remplacement, démission | Insertion contrôlée et décision admin par RPC ; remplaçant approuvé partageant une série |
| Ressources enseignant | Dépôt PDF/DOC/DOCX puis publication admin | Bucket privé, matière/séries assignées et publication contrôlée |
| Messagerie | Élèves de même série, professeurs affectés, échanges de l'équipe | RPC d'autorisation des destinataires et RLS des messages |
| Abonnements | 15 000 Ar / 30 jours ou 145 000 Ar / année scolaire | Référence `AKADEMIA`, transaction et preuve obligatoires, activation admin par RPC |

## Parcours de validation

### Élèves

1. L'élève crée un compte avec ses nom et prénoms, adresse e-mail, téléphone et série.
2. Il confirme son e-mail selon la configuration Supabase Auth.
3. Il se connecte au portail restreint d'inscription et dépose sa photo d'identité, son reçu MVola et l'identifiant de transaction.
4. L'administrateur examine la preuve ; la RPC n'approuve que si les deux objets existent dans le bucket privé `student-enrollment-documents`.
5. Tant que `profiles.registration_status` n'est pas `approved`, le portail complet élève reste bloqué. Le bouton d'actualisation relit le profil depuis Supabase et bascule dans l'espace élève dès que l'administration a approuvé l'inscription.

Le KYC facial n'est pas implémenté. Le système n'effectue aucune comparaison biométrique et ne collecte aucun gabarit facial.

### Enseignants

1. Le candidat crée son compte professionnel et reste au rôle `applicant`.
2. Il renseigne la spécialité proposée, le diplôme et dépose la photo d'identité et la preuve de diplôme.
3. L'administrateur vérifie le dossier, confirme le nom de la matière depuis le PE/RAPE réellement retenu et choisit les séries.
4. Une seule RPC effectue l'approbation et l'affectation ; l'enseignant n'obtient pas son portail si l'affectation échoue.

### Partenaires et promoteurs

- Un partenaire dépose sa candidature, puis, après approbation, soumet chaque cotisation mensuelle de 100 000 Ar avec la référence `FINANCEMENT`, la preuve privée et le transaction ID. L'administrateur saisit une date réelle de fin d'année scolaire, et le système émet le ticket à six chiffres.
- Le ticket partenaire est un numéro de membre secondaire ; il ne se substitue pas à l'identification Supabase Auth.
- Un promoteur est approuvé après contrôle du diplôme minimal Baccalauréat et des pièces. Il reçoit alors un code referral unique. La commission n'est créée qu'après approbation de l'inscription du filleul.

## Règles financières

- Droit annuel d'inscription : 2 000 Ar, MVola `0385528349`, bénéficiaire Nasandratriniaina Julio, référence `AKADEMIA_DROIT`.
- Abonnement aux cours : 15 000 Ar pour 30 jours, ou 145 000 Ar pour l'année scolaire ; MVola `0385528349` ou Binance Pay `820751129`, référence `AKADEMIA`.
- Partenaire : 100 000 Ar/mois, référence `FINANCEMENT`.
- Promoteur : commission 1 000 Ar par élève approuvé ; retrait à partir de 30 000 Ar.
- Enseignant : 6 000 Ar par journée de travail validée ; avance à partir de 30 000 Ar.

L'application n'effectue aucun transfert d'argent et ne vérifie pas automatiquement les transactions auprès de MVola/Binance. Un administrateur doit contrôler réellement le versement avant d'approuver et, pour une dépense, saisir la référence du transfert effectué.

Les anciens abonnements à 5 000 Ar sont conservés comme lignes historiques `legacy`; la migration 08 ne réécrit pas leur prix historique.

## PE / RAPE / FRP

Les séries et le suivi de progression existants sont préservés. Les intitulés de matières et affectations enseignants restent à confirmer par l'équipe pédagogique à partir des documents exacts. Les cours officiels absents des sources ne sont pas inventés. Les dates de publication et la date de fin de l'année scolaire doivent être saisies après validation par la direction. Les nombres du Top 3 enseignant représentent les leçons enregistrées dans `student_progress`, pas un taux de couverture du PE complet.

## Installation SQL

- Nouveau projet : exécuter 01, 02, 03, 05, 06, 07, 08, 09 dans cet ordre ; exécuter le diagnostic 04 en dernier.
- Projet ayant déjà exécuté 01 à 05 : après le test en cours et sauvegarde, exécuter seulement les migrations 06, 07, 08 et 09 qui manquent, dans cet ordre. Ne pas rejouer 01 à 05.
- `04_PRE_LAUNCH_CHECKS.sql` est un diagnostic en lecture seule, pas une migration.

Voir `GUIDE_DEPLOIEMENT.md` pour le détail et les URL de redirection Supabase/Netlify.

## Vérifications locales de cette livraison

- Syntaxe JavaScript de `role-portal.js` et des trois scripts inline contrôlée avec `node --check`.
- Analyse du HTML : identifiants uniques, références de scripts locaux présentes.
- Manifeste PWA analysé comme JSON valide.
- Revue statique des nouvelles migrations et des politiques RLS.

## Non vérifié / dépendances du propriétaire

- La migration 09 n'a pas été exécutée sur le projet Supabase distant depuis cet environnement ; le propriétaire doit confirmer son exécution après les migrations 06–08.
- Les tests Auth, RLS, Storage, RPC, comptes multi-rôles, justificatifs et tickets nécessitent le projet Supabase du propriétaire.
- Aucun paiement ni paie n'a été validé ou envoyé.
- Aucun KYC facial n'est fourni ; il faut un prestataire et un cadre légal/confidentialité approprié.
- Le domaine et l'hébergement HTTPS Netlify restent à configurer/vérifier, comme l'installation sur appareil.
- Le compte administrateur et ses secrets restent gérés exclusivement dans Supabase Auth ; aucun secret n'est livré ici.

## Mise à jour suivante — identité, supervision et accueil des cours

- Nom public harmonisé : Smart Akademia School.
- Le Centre de supervision affiche les élèves par série, validations et paiements en attente, abonnements actifs/expirés, effectifs professionnels approuvés, candidatures/demandes en attente, paiements validés du mois et leçons terminées. Les chiffres sont calculés par une RPC SQL réservée aux administrateurs.
- La page du cours de Philosophie et le lecteur de leçon affichent « Bonjour [nom de l’élève] ! ».
- Le professeur responsable est affiché à partir de l’affectation approuvée dans `teacher_subject_assignments`. Si la série n’a pas d’affectation active, l’application le signale.
- Nouvelle migration requise : `09_SUPERVISION_ET_ENSEIGNANTS_COURS.sql`.
- Vérifications locales effectuées : syntaxe JavaScript, identifiants HTML, références locales et manifeste PWA ; les tests Supabase distants restent à réaliser par le propriétaire.

### Gestion des affectations de cours

L’espace administrateur dispose d’un formulaire pour affecter un enseignant approuvé à une matière et aux séries sélectionnées, par la RPC sécurisée `admin_assign_teacher_subject()` existante en migration 06. La liste des affectations actives est visible dans le même panneau. Pour que le nom apparaisse chez l’élève, l’affectation doit être nommée exactement « Philosophie » et inclure sa série.


## Correctif des parcours d'inscription et de connexion (mise à jour)

- Le site utilise désormais un seul formulaire de connexion commun à tous les rôles. `akademia` est un alias mappé vers l'e-mail Auth configuré ; le rôle est relu côté Supabase et détermine le tableau de bord. La restauration de session admin passe également par la vérification serveur.
- Le formulaire d'inscription élève demande en amont la photo d'identité, la preuve MVola et la référence de transaction avant la création du compte.
- Le formulaire initial des enseignants et promoteurs exige photo d'identité et preuve du diplôme ; le candidat partenaire doit joindre le justificatif de sa première cotisation de 100 000 Ar, avec mode et référence.
- Les documents sont conservés temporairement dans IndexedDB, dans le navigateur courant, en attendant la première session Auth lorsque la confirmation e-mail est activée ; puis ils sont transférés vers des buckets privés. Un changement d'appareil impose de re-sélectionner les justificatifs.
- Migration 10 : autorise l'upload partenaire au stade `applicant`, exige les preuves de cotisation pour l'approbation et crée ensuite une contribution en attente de validation manuelle.
- Diagnostic admin en lecture seule : `supabase/diagnostics/10_DIAGNOSTIC_CONNEXION_ADMIN.sql`.
