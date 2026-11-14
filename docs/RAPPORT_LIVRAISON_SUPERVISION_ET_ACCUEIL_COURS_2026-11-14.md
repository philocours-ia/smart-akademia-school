# Smart Akademia School — rapport de livraison

**Date : 14 novembre 2026**  
**Portée :** harmonisation de l'identité, Centre de supervision administrateur, affectations pédagogiques et accueil personnalisé dans les cours.

## 1. Modifications apportées

- L'application, le titre HTML, les métadonnées PWA et la documentation utilisent le nom officiel **Smart Akademia School**.
- Les ressources graphiques déjà présentes dans le projet sont conservées : elles représentent le chapeau de graduation, le livre ouvert et les instruments d'écriture. Les icônes du manifeste PWA pointent toujours vers les assets du projet.
- La page de cours affiche, pour un élève connecté, `Bonjour [nom du profil] !`.
- Le lecteur d'une leçon affiche le même message au-dessus du contenu.
- Le nom du responsable de Philosophie n'est jamais codé en dur. Il provient d'une affectation active `teacher_subject_assignments` et d'un profil enseignant approuvé, limité aux séries de l'élève.
- En l'absence d'affectation officielle, l'application l'indique explicitement au lieu d'inventer un nom.
- Le Centre de supervision administrateur affiche les effectifs par série, les statuts d'inscription, les abonnements actifs/expirés, les opérations financières en attente, les candidatures, les demandes, les leçons terminées et les montants enregistrés comme validés dans Supabase.
- L'administration dispose d'un formulaire pour affecter un enseignant approuvé à une matière et une ou plusieurs séries. L'enregistrement utilise `admin_assign_teacher_subject()` déjà protégé dans la migration 06.
- Le cache PWA a été renouvelé afin que les appareils installés chargent les nouvelles ressources.

## 2. Migration SQL 09

Fichier : `supabase/migrations/09_SUPERVISION_ET_ENSEIGNANTS_COURS.sql`.

Elle ajoute deux fonctions :

- `get_akademia_admin_supervision()` : agrégats réservés à un administrateur confirmé par `public.is_admin()`.
- `get_my_course_teachers('Philosophie')` : renvoie uniquement les noms des enseignants approuvés actifs affectés à la série de l'élève connecté. Aucun e-mail ni renseignement privé n'est renvoyé.

**Prérequis :** migrations 01 à 08 déjà appliquées. Faire une sauvegarde, vérifier l'historique Supabase et n'exécuter cette migration qu'une fois. Pour un projet déjà à jour jusqu'à 08, exécuter seulement 09. Le diagnostic 04 s'exécute en dernier et reste un script de vérification en lecture seule.

Une fois 09 appliquée, l'administrateur se connecte, ouvre « Affectations pédagogiques », sélectionne un enseignant approuvé, laisse/saisit la matière exacte `Philosophie`, coche la série réelle de l'élève, puis enregistre. Le nom apparaît dans la bannière élève si l'affectation est active et le professeur approuvé.

## 3. Contrôles exécutés localement

| Contrôle | Résultat |
|---|---|
| Syntaxe Node.js des trois scripts inline | Réussie (`node --check`) |
| Syntaxe de `site/role-portal.js` | Réussie (`node --check`) |
| Identifiants HTML | 174, sans doublon |
| Références locales détectées | 12, aucune ressource manquante |
| Manifeste PWA | JSON valide ; nom Smart Akademia School ; icônes présentes |
| Vérification statique des migrations 06–09 | Revue effectuée ; pas d'exécution PostgreSQL distante |

Une tentative de test Chromium/Playwright local n'a pas pu démarrer : l'environnement a bloqué la navigation vers le serveur local avec `net::ERR_BLOCKED_BY_ADMINISTRATOR`. Aucun test bout en bout dans un navigateur réel n'est donc revendiqué.

## 4. Actions encore nécessaires

1. Confirmer que les migrations 06, 07 et 08 sont exécutées dans le bon projet Supabase.
2. Sauvegarder puis exécuter la migration 09 une seule fois.
3. Exécuter le diagnostic 04 en lecture seule.
4. Affecter officiellement les enseignants de Philosophie par série depuis le Centre de supervision.
5. Tester avec au moins un compte admin, deux élèves de séries distinctes et un enseignant approuvé. Vérifier que le nom du professeur est visible seulement pour les séries affectées et que l'appel du RPC admin est refusé à un élève.
6. Tester le site sur le domaine HTTPS réel, déployer sur Netlify et vérifier l'installation sur appareils Android/iOS.

## 5. Limites de sécurité et de validation

- Les vérifications JavaScript et HTML sont locales et statiques. Elles ne démontrent pas le fonctionnement réel des politiques RLS, des RPC, du Storage ou d'Auth sur votre projet Supabase.
- Le Centre de supervision affiche les opérations déclarées approuvées/actives dans la base. Un montant affiché n'est ni un reçu bancaire, ni une confirmation indépendante du versement MVola ou Binance ; aucun virement n'est exécuté par ces fonctions.
- Le nom d'un enseignant n'apparaît que si le profil et l'affectation existent et répondent aux critères SQL. Il faut donc renseigner les affectations réelles dans l'administration ; aucun responsable n'est prérempli artificiellement.
- Aucune clé `service_role`, aucun mot de passe ni secret privé n'a été ajouté au code livré.
- Le site n'a pas été déployé et n'est pas déclaré en production.
