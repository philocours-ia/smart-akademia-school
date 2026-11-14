# Smart Akademia School — dépôt source PWA

Ce dépôt contient l’application web installable **Smart Akademia School**, ses ressources PWA, les scripts Supabase et les documents de déploiement. Smart Akademia School est le nom public utilisé dans l’application, le manifeste PWA, les ressources graphiques et la documentation.

## Arborescence

- `site/` : site statique à publier sur Netlify ou un hébergement HTTPS équivalent.
- `supabase/01_AKADEMIA_supabase_setup.sql` : script de base à utiliser uniquement pour une nouvelle base, après sauvegarde et revue.
- `supabase/migrations/02_MIGRATION_CONNEXION_ADMIN.sql` : autorisation privée du compte administrateur et déclencheur Auth.
- `supabase/migrations/03_HARDEN_PAYMENT_PROOFS.sql` : durcissement des justificatifs de paiement.
- `supabase/diagnostics/04_PRE_LAUNCH_CHECKS.sql` : diagnostic SQL en lecture seule (ce n'est pas une migration).
- `supabase/migrations/05_VALIDATION_INSCRIPTIONS.sql` : première validation admin des inscriptions élèves.
- `supabase/migrations/06_ROLES_CANDIDATURES_FINANCE_MESSAGERIE.sql` : candidatures et portails enseignant/partenaire/promoteur, affectations, commissions, salaires, demandes, ressources et messagerie.
- `supabase/migrations/07_STUDENT_ENROLLMENT_DOCUMENTS.sql` : droit annuel élève, photo d'identité et reçu privés avec décision admin.
- `supabase/migrations/08_SUBSCRIPTION_PLANS_AND_VALIDATION.sql` : abonnements 15 000 Ar/30 jours et 145 000 Ar/année scolaire avec validation serveur.
- `supabase/migrations/09_SUPERVISION_ET_ENSEIGNANTS_COURS.sql` : indicateurs admin agrégés côté serveur et récupération du nom du professeur de Philosophie affecté à la série de l’élève.
- `docs/` : guide, état de préparation, vérification de connexion et référentiel PE/RAPE.
- `data/` : banque de citations exportée.

## Ordre d'installation Supabase

### Nouveau projet

1. Créer le projet Supabase.
2. Exécuter `01_AKADEMIA_supabase_setup.sql` une seule fois.
3. Exécuter `02_MIGRATION_CONNEXION_ADMIN.sql`.
4. Créer ou mettre à jour le compte Auth autorisé `julio7271@gmail.com` dans Supabase Authentication.
5. Saisir le mot de passe initial uniquement dans Supabase Auth. Ne jamais le placer dans le SQL, le HTML, GitHub, un fichier `.env` livré au navigateur ou cette documentation. La première connexion impose son remplacement par un mot de passe robuste d'au moins 12 caractères.
6. Exécuter `03_HARDEN_PAYMENT_PROOFS.sql`.
7. Exécuter les migrations 05, 06, 07, 08 et 09 dans cet ordre.
8. Exécuter `04_PRE_LAUNCH_CHECKS.sql` à la fin ; c'est un diagnostic en lecture seule, et non une migration.

### Projet déjà initialisé

Ne pas relancer le script 01 sur une base contenant des données sans sauvegarde et revue de migration. Vérifier d'abord que les scripts 01 et 02 ont bien été appliqués. Si les migrations 01 à 05 sont déjà présentes et validées, exécuter uniquement les nouvelles migrations 06, 07, 08 et 09 encore absentes, dans cet ordre. Puis relancer le diagnostic 04. Ne pas rejouer les migrations déjà appliquées.

Les anciens fichiers de migration de classe/programme qui ne figurent pas dans ce dépôt ne doivent pas être réintroduits sans revue : certains anciens déclencheurs d'inscription peuvent remplacer le déclencheur sécurisé actuel. Ne pas relancer 01 sur une base active sans sauvegarde. Ne pas relancer 02 après le provisionnement et le changement du mot de passe : elle remettrait `must_change_password` à `true` pour le compte admin et forcerait une nouvelle modification.

## Configuration déjà présente

`site/index.html` contient le Project URL Supabase, la clé publique **publishable** fournie et l'adresse e-mail administrateur. Une clé publishable est destinée au navigateur ; elle n'est pas une clé secrète. Aucune clé `sb_secret_`, `service_role`, aucun mot de passe de base de données et aucun secret d'administration ne doivent apparaître dans le dépôt ou le site.

L'identifiant affiché dans le portail admin est `akademia`. Il sert uniquement à sélectionner le compte administrateur configuré ; l'authentification réelle est effectuée par Supabase Auth avec l'adresse e-mail autorisée et le mot de passe saisi par le propriétaire.

## Déploiement web/PWA

- Pour un dépôt Git connecté à Netlify : définir `site` comme répertoire de publication et laisser la commande de build vide.
- Pour un déploiement manuel : publier le contenu de `site/` à la racine du site (ne pas publier le dossier `supabase/` ni les documents internes).
- Utiliser HTTPS. Les règles `_headers` ajoutent des en-têtes de sécurité et évitent de garder longtemps en cache le HTML, le manifeste et le service worker.
- Après attribution du domaine, mettre à jour Supabase Authentication → URL Configuration avec l'URL du site et les URL de redirection exactes.
- Installation Android : Chrome → menu → Installer l'application / Ajouter à l'écran d'accueil.
- Installation iOS : Safari → Partager → Sur l'écran d'accueil.

## Sécurité et limites fonctionnelles

- Deux portes d'entrée : élèves (`/`) et administration (`/administration.html`). Aucun lien ou bouton d'accès administrateur n'est présent dans la navigation élève. L'URL admin n'est pas un secret : Supabase Auth, `is_admin()` et les politiques RLS constituent la sécurité réelle.
- Le compte administrateur ne peut ouvrir le tableau de bord qu'après vérification du rôle côté Supabase et changement du mot de passe initial.
- Le droit annuel d'inscription est de 2 000 Ar via MVola avec la référence `AKADEMIA_DROIT`. Il est distinct des abonnements aux cours.
- L'abonnement mensuel aux cours est de 15 000 Ar pour 30 jours ; la formule annuelle est de 145 000 Ar jusqu'à une date réelle de fin d'année scolaire saisie par l'administrateur.
- Les abonnements se règlent via MVola ou Binance Pay avec la référence `AKADEMIA`, preuve et identifiant de transaction obligatoires. Le paiement est vérifié manuellement ; aucun transfert ou contrôle automatique auprès des opérateurs n'est réalisé.
- Les preuves et pièces d'identité sont stockées dans des buckets privés. Les décisions d'approbation passent par des RPC protégées par le rôle admin et les RLS.
- Les partenaires règlent 100 000 Ar/mois avec la référence `FINANCEMENT`; les promoteurs touchent une commission de 1 000 Ar par inscription élève approuvée avec un minimum de demande de 30 000 Ar. Les enseignants sont rémunérés à 6 000 Ar par journée de travail enregistrée par l'administration. Les paiements réels restent manuels.
- Le ticket élève ou partenaire n'est pas un mot de passe et ne remplace pas Supabase Auth.
- Le rappel de renouvellement est affiché dans l'application lorsqu'il reste 7 jours ou moins. Aucun e-mail/SMS automatique n'est programmé.
- Le shell PWA peut être mis en cache, mais les données Supabase, l'authentification et les bibliothèques externes nécessitent une connexion Internet. Ce n'est pas une application entièrement hors ligne.
- Le calendrier de sortie des leçons est volontairement vide jusqu'à validation des dates pédagogiques. Les leçons complètes restent verrouillées tant que la série, l'abonnement actif et la date de sortie ne concordent pas.

Consulter `docs/GUIDE_DEPLOIEMENT.md` et `docs/ETAT_NOUVELLES_FONCTIONNALITES_2026-11-14.md` avant toute mise en ligne. Les anciennes notes d'état conservées dans `docs/` sont historiques ; le guide actuel décrit la livraison 06–09.

## Nouveautés de la mise à jour supervision et cours

- Le tableau de bord administrateur comprend un Centre de supervision alimenté par la RPC protégée `get_akademia_admin_supervision()`.
- La page de cours et le lecteur de leçon affichent « Bonjour [nom de l’élève] ! ».
- Le nom du professeur responsable de Philosophie est obtenu depuis les affectations approuvées `teacher_subject_assignments` via la RPC `get_my_course_teachers()`. Si aucune affectation n’existe, l’application l’indique explicitement au lieu d’inventer un responsable.
- Appliquer la migration 09 après les migrations 06–08 pour activer ces fonctions. L’administration peut saisir ou mettre à jour les affectations enseignant/matière/séries depuis le panneau « Affectations pédagogiques ».
