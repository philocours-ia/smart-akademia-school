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

## Ordre complet — projet neuf

01 → 02 → provisionnement compte Auth admin → 03 → 05 → 06 → 07 → 08 → 09 → diagnostic 04.

## Base déjà en test avec 01 à 05

Après sauvegarde et confirmation des migrations déjà appliquées, exécuter 06 → 07 → 08 → 09. Si l'une d'elles est déjà appliquée, ne pas la rejouer. Ne jamais rejouer 01 sur une base active sans procédure de migration et sauvegarde. Éviter de rejouer 02 : elle réactive le verrou de changement du mot de passe admin.

Les fichiers sont des scripts SQL source. Leur présence dans ce dépôt ne prouve pas leur exécution dans un projet Supabase.


La migration 09 ajoute deux RPC : `get_akademia_admin_supervision()` (admin uniquement) et `get_my_course_teachers()` (élève approuvé, affectations limitées à sa série). La bannière de cours affiche le nom de l'enseignant uniquement lorsqu'une affectation active et approuvée existe dans `teacher_subject_assignments`.
