# Smart Akademia School — Stabilisation des rôles

**Date : 16 novembre 2026**  
**Branche :** `fix/role-stabilisation-2026-11-16`

## Périmètre du correctif

Cette série consolide les incohérences constatées entre l'interface, les fonctions RPC et les migrations SQL. Elle ne modifie pas directement la base Supabase distante.

### 1. Rôles, séries et affectations

- Ajout de la migration 12 qui contient les deux RPC utilisées par le navigateur : `admin_decide_role_application()` et `get_my_course_assignments()`.
- Harmonisation des contraintes de série sur les profils, abonnements, messages et calendrier des cours.
- Les nouvelles inscriptions élèves et les nouvelles affectations sont limitées à **Troisième (T9), Terminale L, Terminale S et Terminale OSE**.
- Les anciennes valeurs (Seconde et Premières historiques) restent acceptées par les contraintes afin de préserver les comptes déjà enregistrés.
- La fonction de création Auth conserve le traitement de l'allowlist administrateur, le changement obligatoire du mot de passe administrateur et le parcours limité des candidats.
- La fonction de validation d'un enseignant applique l'approbation du compte et l'affectation des matières/séries au sein de la même transaction.

### 2. Candidatures professionnelles

- Le formulaire demande les coordonnées MVola nominatives avant la création du compte : numéro, nom exact du titulaire et déclaration de propriété.
- Après confirmation e-mail et connexion, le transfert des justificatifs en stockage privé enregistre aussi les coordonnées MVola dans le profil.
- Les candidats existants peuvent compléter ou actualiser les coordonnées dans leur portail.
- Une candidature en attente reste visible ; l'administration peut corriger le statut après contrôle.
- Une candidature rejetée peut être redéposée sur le même compte, sans créer un deuxième compte. Une contrainte partielle limite à une seule candidature en attente par type.
- Le titulaire MVola doit être vérifié manuellement par l'administration avant approbation. Modifier le numéro ou le titulaire invalide la vérification antérieure.

### 3. Partenaires et cotisations

La migration 13 d'origine est conservée. La migration 14 apporte les corrections complémentaires :
- Une simple reconnexion ou sauvegarde à coordonnées inchangées ne réinitialise plus la vérification du titulaire.
- L'approbation d'un partenaire conserve les contrôles de migration 10 : engagement mensuel, preuve privée, référence et montant attendu.
- L'approbation du rôle partenaire crée une cotisation **en attente**. Elle ne marque jamais le paiement comme reçu ; l'administration doit encore contrôler cette cotisation séparément.

### 4. Portail administrateur et PWA

- Ajout d'une rubrique admin dédiée aux profils MVola professionnels déjà approuvés.
- Ajout de l'action d'administration pour enregistrer le contrôle manuel du titulaire.
- Le service worker utilise le cache v18 et ne remplace plus le cache de `index.html` par une réponse de navigation vers une autre page, notamment la redirection d'administration.
- Un workflow GitHub Actions vérifie la syntaxe JavaScript et la présence des principaux raccordements RPC/migrations.

## Ordre des migrations

Sur une base neuve ou une base dont l'historique confirme qu'aucune de ces migrations n'a déjà été exécutée :

`01 → 02 → provisionnement admin → 03 → 05 → 06 → 07 → 08 → 09 → 10 → 12 → 13 → 14`

Les diagnostics 04 et 11 sont en lecture seule. Consulter `supabase/MIGRATIONS.md` pour le détail.

**Base déjà en service :** vérifier l'historique réel de migration dans Supabase avant toute exécution. Si la migration 12 ou 13 a déjà été appliquée manuellement, vérifier son contenu et son résultat avant de lancer la 14. Ne pas rejouer les migrations déjà exécutées et ne jamais rejouer le script initial 01 sur une base active sans procédure de sauvegarde et de reprise.

## Scénarios de recette à effectuer

1. Créer un compte élève neuf en Troisième puis en Terminale L/S/OSE ; vérifier le statut initial et la validation du dossier.
2. Confirmer qu'une nouvelle inscription avec une ancienne série n'est plus proposée, sans bloquer la connexion des anciens élèves déjà inscrits.
3. Créer un candidat enseignant, téléverser les pièces, confirmer l'e-mail, se connecter, vérifier le transfert privé, puis contrôler les coordonnées MVola dans l'espace admin.
4. Vérifier le titulaire MVola ; approuver l'enseignant avec matière et séries ; confirmer que le portail passe au rôle enseignant et que les affectations sont visibles.
5. Créer un candidat partenaire, contrôler le titulaire MVola, approuver le rôle, puis confirmer qu'une cotisation en attente est créée et que le ticket n'est généré qu'après validation distincte de la cotisation.
6. Tester un promoteur, son code de parrainage et les rôles/droits correspondants.
7. Refuser une candidature, la corriger et la redéposer depuis le même compte ; vérifier qu'il n'existe qu'une seule demande en attente de ce type.
8. Tester les accès RLS/Storage avec plusieurs comptes distincts : candidat, enseignant, partenaire, promoteur, élève et administrateur.
9. Tester le service worker en ligne/hors ligne et ouvrir puis quitter `administration.html` afin de vérifier que le cache principal reste la véritable page d'accueil.

## État des vérifications dans cette branche

- Les modifications sont isolées sur une branche GitHub ; la branche principale n'a pas été modifiée.
- Un workflow CI est ajouté pour vérifier la syntaxe des scripts JavaScript et quelques raccordements critiques.
- **Aucune connexion au projet Supabase distant n'a été effectuée dans cette session.** L'exécution réelle des migrations, l'état RLS/Storage, les comptes Auth, la vérification MVola et le déploiement Netlify restent à valider dans les environnements du propriétaire.
- Les paiements sont toujours contrôlés manuellement. Ce correctif ne crée pas d'intégration API MVola Merchant Payment et ne déclenche aucun transfert d'argent.
