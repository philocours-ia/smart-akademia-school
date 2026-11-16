# Historique et ordre des migrations Smart Akademia School

| Numéro | Fichier | Objet | Exécution |
|---|---|---|---|
| 01 | `01_AKADEMIA_supabase_setup.sql` | Schéma initial, accès de base, progression, abonnements et cours protégés | Une seule fois sur une nouvelle base |
| 02 | `migrations/02_MIGRATION_CONNEXION_ADMIN.sql` | Allowlist admin et provisioning Auth | Après 01 ; ne pas rejouer sur base active sans revue |
| 03 | `migrations/03_HARDEN_PAYMENT_PROOFS.sql` | Durcissement des preuves de paiement | Après 01/02, une seule fois |
| 04 | `diagnostics/04_PRE_LAUNCH_CHECKS.sql` | Vérifications RLS/Storage en lecture seule | À la fin ; diagnostic uniquement |
| 05 | `migrations/05_VALIDATION_INSCRIPTIONS.sql` | Validation initiale des inscriptions élèves | Après 01–03 |
| 06 | `migrations/06_ROLES_CANDIDATURES_FINANCE_MESSAGERIE.sql` | Candidatures, rôles, affectations, partenaires, promoteurs, finance, staff, ressources, messagerie | Après 01–05 |
| 07 | `migrations/07_STUDENT_ENROLLMENT_DOCUMENTS.sql` | Pièces privées et droit annuel d'inscription élève | Après 01–06 |
| 08 | `migrations/08_SUBSCRIPTION_PLANS_AND_VALIDATION.sql` | Plans d'abonnement et décision admin sécurisée | Après 01–07 |
| 09 | `migrations/09_SUPERVISION_ET_ENSEIGNANTS_COURS.sql` | Centre de supervision admin et nom des enseignants de Philosophie affectés à la série de l'élève | Après 01–08 |
| 10 | `migrations/10_PREUVES_AVANT_INSCRIPTION_ET_PARTENAIRE.sql` | Autorise le pré-dépôt du justificatif de cotisation partenaire et exige son rattachement à la candidature avant approbation | Après 01–09 |
| 11 | `diagnostics/11_DIAGNOSTIC_PORTAILS_UTILISATEURS.sql` | Diagnostic en lecture seule des portails | Diagnostic uniquement, pas une migration |
| 12 | `migrations/12_TROISIEME_ET_VALIDATION_CANDIDATURES.sql` | Classe Troisième/T9, limites des nouvelles inscriptions, RPC explicite de décision admin, liste des enseignants affectés | Après 01–10 |
| 13 | `migrations/13_MVOLA_COORDONNEES_ET_PREPARATION_PAIE.sql` | Numéros MVola nominatifs, vérification administrative des titulaires et garde serveur avant clôture de paie | Après 01–10 et 12 |
| 14 | `migrations/14_STABILISATION_MVOLA_ET_CANDIDATURES.sql` | Préserve la vérification MVola lorsqu'un profil inchangé est rechargé et restaure les contrôles de la première cotisation partenaire à l'approbation | Après 01–13 |

## Ordre complet — projet neuf

01 → 02 → provisionnement compte Auth admin → 03 → 05 → 06 → 07 → 08 → 09 → 10 → 12 → 13 → 14 → diagnostics 04 et 11.

## Base déjà en test avec 01 à 05

Après sauvegarde et confirmation des migrations déjà appliquées, exécuter 06 → 07 → 08 → 09 → 10. Si l'une d'elles est déjà appliquée, ne pas la rejouer. Ne jamais rejouer 01 sur une base active sans procédure de migration et sauvegarde. Éviter de rejouer 02 : elle réactive le verrou de changement du mot de passe admin.

Les fichiers sont des scripts SQL source. Leur présence dans ce dépôt ne prouve pas leur exécution dans un projet Supabase.


La migration 09 ajoute deux RPC : `get_akademia_admin_supervision()` (admin uniquement) et `get_my_course_teachers()` (élève approuvé, affectations limitées à sa série). La bannière de cours affiche le nom de l'enseignant uniquement lorsqu'une affectation active et approuvée existe dans `teacher_subject_assignments`.


La migration 10 n'est pas une migration de login ; elle permet de téléverser la preuve de première cotisation d'un partenaire pendant que son profil est encore candidat, puis inscrit une cotisation en attente lorsque la candidature est approuvée. La validation de paiement reste manuelle.


La migration 12 conserve les anciennes valeurs de série dans le schéma afin de ne pas rendre les anciens dossiers illisibles, mais les nouvelles inscriptions élèves et les nouvelles affectations sont limitées à Troisième (T9) et Terminale L/S/OSE. Elle ajoute la fonction `admin_decide_role_application()` utilisée par les boutons de validation et `get_my_course_assignments()` pour afficher les enseignants affectés à la série d'un élève. L'approbation d'une candidature partenaire ne valide pas automatiquement son versement : la cotisation initiale reste à vérifier manuellement avant génération du ticket.


La migration 13 ajoute les coordonnées MVola des candidats enseignants, partenaires et promoteurs, leurs champs de mise à jour dans les portails et les RPC de contrôle admin. Elle prépare la paie enseignants/promoteurs via la file de demandes et une exportation de rapprochement ; ce CSV n'est pas le modèle d'import officiel MVola. La fonction `admin_review_finance_request()` est renforcée côté serveur : une demande ne peut être marquée payée que si le compte MVola du bénéficiaire est vérifié et si une référence de transfert réelle est fournie.

L'API Merchant Payment pour les encaissements clients n'est pas encore implémentée par la migration 13. Elle nécessite la documentation technique et les paramètres Sandbox liés au compte MVola Developer du propriétaire, puis la procédure GO LIVE MVola. Les secrets restent exclusivement côté backend Supabase Edge Functions.


## Correctifs de stabilisation — 16 novembre 2026

La migration 12 est désormais présente dans le dépôt. Elle rend cohérents les nouvelles séries actives (Troisième et Terminale L/S/OSE), ajoute les RPC utilisées par les portails (`admin_decide_role_application()` et `get_my_course_assignments()`) et autorise le redépôt d'une candidature rejetée sur le même compte, avec une seule candidature en attente par type.

La migration 13 est conservée comme migration historique. La migration 14 apporte les corrections complémentaires : une simple reconnexion ne réinitialise plus la vérification du compte MVola si ses coordonnées n'ont pas changé ; l'approbation partenaire conserve la vérification de la preuve et crée seulement une cotisation en attente. L'encaissement n'est jamais marqué comme payé automatiquement.

**Base Supabase déjà utilisée :** consulter l'historique réel des migrations dans Supabase avant exécution. Si 12 ou 13 ont été exécutées manuellement, vérifier leur contenu et leur résultat avant de lancer 14. Ne jamais rejouer 01–13 « pour essayer » sur une base contenant déjà des données.
