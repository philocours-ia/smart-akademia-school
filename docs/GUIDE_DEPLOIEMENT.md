# Smart Akademia School — guide d'installation et de mise en ligne PWA

**État au 14 novembre 2026 :** les fichiers de préparation sont cohérents et contrôlés statiquement. Le site n'est pas déployé, aucun domaine n'est attribué et l'authentification réelle n'a pas pu être testée depuis cet environnement. Ne pas annoncer l'application comme étant en ligne avant un déploiement HTTPS vérifié.

> **Nom officiel de la plateforme : Smart Akademia School.** Le nom est harmonisé dans l’application, le manifeste PWA, les ressources graphiques et la documentation de cette livraison.

## 1. Contenu livré

- `site/index.html` : application élève, connexion/inscription, suivi, cours, citations, bibliothèque, exercices, forum, assistance et « Qui sommes-nous ? ».
- `site/administration.html` : porte d'entrée distincte vers le portail administrateur.
- `site/manifest.webmanifest` : nom, portée, affichage autonome et icônes PWA.
- `site/service-worker.js` : cache du shell same-origin, sans mise en cache des réponses Supabase.
- `site/icons/` et `site/assets/` : icônes 192/512, icône Apple, favicon et logo.
- `site/_headers` : en-têtes HTTP pour l'hébergement Netlify.
- `supabase/01_AKADEMIA_supabase_setup.sql` : schéma, RLS, stockage privé, progression, abonnements et contenu protégé.
- `supabase/migrations/02_MIGRATION_CONNEXION_ADMIN.sql` : allowlist admin privée et déclencheur d'attribution du rôle.
- `supabase/migrations/03_HARDEN_PAYMENT_PROOFS.sql` : contrôle côté base de l'existence du justificatif et protection contre sa suppression par l'élève après enregistrement.
- `supabase/diagnostics/04_PRE_LAUNCH_CHECKS.sql` : requêtes de contrôle en lecture seule.
- `supabase/migrations/05_VALIDATION_INSCRIPTIONS.sql` : validation des profils élèves.
- `supabase/migrations/06_ROLES_CANDIDATURES_FINANCE_MESSAGERIE.sql` : candidatures professionnelles, affectations, finance, messages et ressources enseignant.
- `supabase/migrations/07_STUDENT_ENROLLMENT_DOCUMENTS.sql` : dossier élève et preuve du droit annuel.
- `supabase/migrations/08_SUBSCRIPTION_PLANS_AND_VALIDATION.sql` : abonnements mensuel/annuel et décision admin protégée.
- `supabase/migrations/09_SUPERVISION_ET_ENSEIGNANTS_COURS.sql` : Centre de supervision administrateur et affichage sécurisé des enseignants de Philosophie affectés.

## 2. Portes d'entrée et contrôle d'accès

- **Élèves :** racine du site, `/` ou `/index.html`.
- **Tous les profils :** même formulaire de connexion à la racine du site. L’administrateur saisit `akademia`; les autres profils saisissent leur adresse e-mail. Le rôle Supabase décide de l’espace ouvert.
- Aucun lien ni bouton administrateur n'est affiché dans les menus élève.
- L'URL d'administration n'est pas une protection. Le rôle `admin` est attribué côté base uniquement à l'adresse autorisée par la table privée `akademia_admin_allowlist` ; le rôle n'est jamais accepté depuis les métadonnées envoyées par le navigateur.
- Après connexion, le profil Supabase doit avoir `role = 'admin'`. Le mot de passe initial doit être changé ; le trigger `auth.users` ne lève le verrou qu'après changement effectif du hash Auth. L'application appelle ensuite `rpc('is_admin')` avant d'afficher le tableau de bord.
- Les politiques RLS protègent les profils, abonnements, messages, progressions, contenus de cours, calendrier et fichiers Storage. Le contrôle JavaScript ne remplace jamais ces politiques.

L'identifiant affiché est `akademia`. Il est mappé vers l'adresse Auth `julio7271@gmail.com` dans la configuration publique du site. Le mot de passe n'est pas stocké dans le HTML.

## 3. Configuration Supabase

### Nouveau projet

1. Créer un projet Supabase et conserver le Project URL et la clé publishable.
2. Dans SQL Editor, exécuter `supabase/01_AKADEMIA_supabase_setup.sql` une seule fois.
3. Exécuter `supabase/migrations/02_MIGRATION_CONNEXION_ADMIN.sql`.
4. Dans Authentication → Users, créer ou mettre à jour l'utilisateur `julio7271@gmail.com`.
5. Saisir le mot de passe initial demandé directement dans Supabase Auth, jamais dans le dépôt, le SQL, un fichier HTML ou la conversation. Vérifier que l'adresse est confirmée. Le profil doit afficher `role = admin`, `series = Administrateur` et `must_change_password = true` avant le premier accès.
6. Exécuter `supabase/migrations/03_HARDEN_PAYMENT_PROOFS.sql`.
7. Exécuter `supabase/diagnostics/04_PRE_LAUNCH_CHECKS.sql` et vérifier qu'aucune politique permissive héritée n'accorde un accès trop large à `storage.objects` ou aux tables applicatives.

### Projet déjà créé

Le propriétaire a indiqué avoir déjà exécuté les scripts initiaux et confirmé que le profil administrateur apparaît comme `admin`. Ne pas réexécuter le script 01 sur la base active sans sauvegarde. Vérifier l'historique SQL, exécuter la migration 03 une seule fois si elle n'a pas été appliquée, puis lancer le diagnostic 04.

**Provisionnement du mot de passe :** cette préparation ne dispose pas d'une clé secrète Supabase ni d'un accès propriétaire au tableau de bord. Elle ne peut donc pas écrire/modifier le mot de passe Auth à distance. Le propriétaire doit saisir le mot de passe temporaire dans Supabase Authentication → Users. La première connexion doit le remplacer par un mot de passe robuste d'au moins 12 caractères. Ne jamais inscrire la valeur temporaire dans les fichiers livrés.

### URL de site et redirections

Après avoir obtenu le domaine Netlify ou le domaine personnalisé :

1. Supabase → Authentication → URL Configuration.
2. Définir `Site URL` sur l'URL HTTPS réelle.
3. Ajouter les URL exactes de redirection utilisées par les liens de confirmation et de récupération de mot de passe (racine et `index.html` du domaine publié).
4. Tester confirmation d'e-mail, récupération et changement de mot de passe depuis le domaine réel.

## 4. Déploiement Netlify

### Depuis GitHub

1. Décompresser le paquet source et pousser son contenu dans un dépôt privé.
2. Dans Netlify, créer un nouveau site depuis Git.
3. Définir le répertoire de publication sur `site`.
4. Laisser la commande de build vide : il s'agit d'un site statique.
5. Déployer, puis vérifier l'URL HTTPS générée.

### Déploiement manuel

Utiliser le paquet Netlify fourni : son contenu doit être placé à la racine web. Ne publier ni `supabase/`, ni `docs/`, ni les scripts SQL.

### Domaine et HTTPS

Netlify fournit un domaine HTTPS de test. Pour un domaine personnalisé, le rattacher dans Netlify, attendre l'émission du certificat TLS, puis mettre à jour Supabase Auth URL Configuration. Ne pas installer la PWA avant que le site soit servi en HTTPS (sauf `localhost` pour un test local).

## 5. Installation sur téléphone

- Android : ouvrir le domaine HTTPS dans Chrome → menu ⋮ → Installer l'application ou Ajouter à l'écran d'accueil.
- iPhone : ouvrir le domaine HTTPS dans Safari → Partager → Sur l'écran d'accueil.

Le manifeste référence les icônes 192×192 et 512×512, et le service worker renouvelle le cache avec le nom `smart-akademia-school-shell-v13-single-login-preregister-proofs`. Après une mise à jour, fermer puis rouvrir l'application installée si l'ancien cache reste visible.

**Limite hors ligne :** le shell statique et les icônes sont mis en cache ; Supabase, les comptes, les paiements, les cours et les CDN nécessitent Internet. Ne pas présenter cette PWA comme un mode hors ligne complet.

## 6. Modules et règles métier intégrés

### Élèves : inscription annuelle et accès aux cours

- Les séries proposées sont Seconde, Première L/S/OSE et Terminale L/S/OSE. Le profil générique `Première` est conservé uniquement pour reprise/diagnostic et doit être affecté à une série par l’administration.
- Le formulaire d’inscription demande avant la création du compte la photo d’identité, le reçu MVola et l’identifiant de transaction pour le droit annuel de **2 000 Ar**, avec la référence `AKADEMIA_DROIT`, au **0385528349 — Nasandratriniaina Julio**. Si la confirmation e-mail est activée, les pièces sont temporairement conservées dans IndexedDB et téléversées après la première connexion sur le même navigateur.
- Les fichiers du dossier annuel sont placés dans le bucket privé `student-enrollment-documents`. La validation par l’administrateur vérifie côté SQL que les deux fichiers existent réellement avant de changer le profil à `approved`. Le paiement demeure une vérification humaine à partir du reçu et de l’historique MVola.
- La vérification faciale/KYC n'est pas activée. Aucun scan facial ni donnée biométrique n'est demandé ou traité par cette version ; un prestataire, une base légale, un consentement explicite et une politique de conservation seront nécessaires avant d'ajouter ce contrôle.
- Les cours complets restent accessibles après abonnement validé : **15 000 Ar pour 30 jours** ou **145 000 Ar pour l’année scolaire**. Moyens acceptés : MVola `0385528349` ou Binance Pay `820751129`, référence obligatoire `AKADEMIA`, preuve et identifiant de transaction requis.
- La validation d'un abonnement est une RPC admin : `admin_activate_student_subscription`. Elle vérifie la référence, le transaction ID et l'existence de la preuve Storage avant d'activer et d'émettre un nouveau ticket. Pour le mensuel, le renouvellement ajoute 30 jours à l'expiration active. Pour l'annuel, l'administrateur saisit la date réelle de fin de l'année scolaire ; aucune date n'est préremplie ou inventée.
- Les demandes de renouvellement créent de nouvelles lignes. Le ticket est un justificatif/numéro d'accès associé à la souscription, pas un mot de passe ni un substitut à Supabase Auth. Le rappel de renouvellement est affiché dans l'application lorsque l'échéance approche ; aucun SMS ou e-mail automatique n'est programmé.

### Candidatures professionnelles, enseignants, partenaires, promoteurs

- Les comptes candidats sont enregistrés sous le rôle limité `applicant`. Le rôle final n'est attribué qu'après décision admin côté SQL.
- **Enseignant :** nom, e-mail, téléphone, spécialité proposée, diplôme, photo d'identité et preuve du diplôme. L'administrateur vérifie le dossier, confirme le nom de matière d'après les PE/RAPE retenus et affecte le professeur à une ou plusieurs séries. L'approbation et l'affectation sont regroupées dans une RPC transactionnelle.
- **Partenaire :** le nom de la personne/organisation, l'acceptation de la contribution mensuelle de **100 000 Ar**, le mode de paiement, l'identifiant de transaction et la preuve du premier versement sont exigés dans le formulaire initial, avant la création du compte. Le dossier et le justificatif sont transférés dans un bucket privé après la première session Auth. Après approbation de la candidature, une cotisation en attente est créée ; l'administrateur vérifie séparément le justificatif et la valide. Le ticket numérique à six chiffres n'est généré qu'après validation du paiement et saisie de la date réelle de fin d'année scolaire ; il ne remplace jamais la connexion Supabase Auth. L'accès d'audit aux cours est conditionné par une cotisation active et un ticket annuel valide.
- **Promoteur :** niveau Bac minimum avec photo et preuve de diplôme. Après approbation, un code de parrainage de huit caractères est attribué. Une commission de **1 000 Ar** est inscrite lorsque l'élève référé a lui-même obtenu l'approbation de son inscription. Le seuil de demande de paiement est **30 000 Ar**.
- Les pièces des candidatures et les reçus partenaires sont stockés dans des buckets privés. Les URL signées utilisées par l'administration expirent après 15 minutes. Des politiques Storage restrictives supplémentaires empêchent des politiques permissives héritées d'ouvrir ces buckets par inadvertance.

### Enseignants, paie, demandes administratives et messagerie

- Espace enseignant : matières/séries affectées, progression enregistrée des élèves des séries autorisées, Top 3 selon le nombre de leçons terminées enregistrées, dépôt de ressources PDF/DOC/DOCX, finances et messagerie.
- Le calcul de paie utilise **6 000 Ar par journée de travail validée par l'administration**. L'administrateur enregistre les jours travaillés. La demande de salaire porte sur le cumul acquis non encore réclamé ; les demandes d'avance et de paiement en attente ou déjà approuvées sont déduites pour éviter le double compte. Les avances ne sont accessibles qu'à partir de **30 000 Ar** disponibles.
- L'administrateur doit effectuer le virement réel avant de marquer une demande financière comme payée et doit saisir sa référence de transfert. La plateforme ne déclenche aucun transfert MVola/Binance.
- Les enseignants peuvent déposer une demande de congé, de remplacement ou de démission. Le formulaire exige les dates pour un congé/remplacement, le lieu pour un congé et le choix d'un remplaçant pour un remplacement. Un remplaçant proposé doit être un enseignant approuvé qui partage au moins une série affectée.
- Les messages entre élèves sont limités aux élèves de la même série ; les échanges élève-enseignant sont restreints aux affectations pertinentes. Les partenaires et promoteurs ne peuvent écrire qu'à l'administration. Les contrôles sont appliqués côté SQL/RLS, pas uniquement dans l'interface.

### Limites pédagogiques et institutionnelles

- Le tableau de bord enseignant compte uniquement les activités présentes dans `student_progress`. Il ne calcule pas à lui seul une progression officielle complète sur l'ensemble du PE.
- Les matières et séries d'un enseignant sont confirmées manuellement à partir des sources pédagogiques réellement disponibles. Aucun catalogue officiel nouveau n'est présélectionné.
- Le calendrier de publication des cours reste vide tant que les dates exactes n'ont pas été confirmées par la direction pédagogique.
- La rubrique « Qui sommes-nous ? » est conservée et reste à compléter par le propriétaire.

## 7. Migrations Supabase : ordre et précautions

| N° | Fichier | Rôle | Type |
|---|---|---|---|
| 01 | `supabase/01_AKADEMIA_supabase_setup.sql` | Schéma de base, contenu protégé, abonnements et RLS initiales | Installation initiale |
| 02 | `supabase/migrations/02_MIGRATION_CONNEXION_ADMIN.sql` | Allowlist et rôle admin Auth | Migration |
| 03 | `supabase/migrations/03_HARDEN_PAYMENT_PROOFS.sql` | Durcissement des preuves de paiement | Migration |
| 04 | `supabase/diagnostics/04_PRE_LAUNCH_CHECKS.sql` | Audit de politiques et configuration, lecture seule | Diagnostic, pas une migration |
| 05 | `supabase/migrations/05_VALIDATION_INSCRIPTIONS.sql` | Statut et validation initiale des inscriptions élèves | Migration |
| 06 | `supabase/migrations/06_ROLES_CANDIDATURES_FINANCE_MESSAGERIE.sql` | Candidatures, rôles, affectations, partenaires, promoteurs, finances, demandes, cours et messages | Migration |
| 07 | `supabase/migrations/07_STUDENT_ENROLLMENT_DOCUMENTS.sql` | Droit annuel élève, pièces privées et vérification des pièces à la validation | Migration |
| 08 | `supabase/migrations/08_SUBSCRIPTION_PLANS_AND_VALIDATION.sql` | Plans mensuel/annuel et validation serveur des abonnements | Migration |
| 09 | `supabase/migrations/09_SUPERVISION_ET_ENSEIGNANTS_COURS.sql` | Centre de supervision admin et affichage des enseignants de Philosophie affectés par série | Migration |

### Base vierge

1. Exécuter 01 une seule fois.
2. Exécuter 02, créer/valider ensuite le compte Auth administrateur autorisé.
3. Exécuter 03, puis 05, 06, 07, 08 et 09, dans cet ordre.
4. Exécuter 04 en dernier pour le diagnostic en lecture seule.

### Base ayant déjà reçu les migrations 01 à 05

Après avoir terminé le test courant et confirmé que 01 à 05 sont réellement appliquées, exécuter uniquement les migrations 06, 07, 08 et 09 encore absentes, dans cet ordre. Ne pas rejouer 01, 02, 03 ou 05 sur une base active. Si une de ces migrations a déjà été appliquée, ne pas la rejouer ; vérifier l'historique et l'état réel de la base.

Les migrations doivent être testées sur une sauvegarde ou une base de recette avant production. Les fichiers 06 à 09 sont conçus pour les prérequis indiqués en tête de chaque fichier, mais leur exécution PostgreSQL distante n'a pas été faite depuis cet environnement.

## 8. Tests effectués et limites

### Contrôles locaux effectués pour cette mise à niveau

- `node --check` sur `site/role-portal.js` et sur chacun des scripts JavaScript intégrés à `index.html`.
- Analyse HTML : 174 identifiants `id`, aucune duplication ; 12 références locales vérifiées, aucune ressource manquante.
- Analyse JSON du manifeste PWA.
- Contrôle de présence des fichiers et ressources PWA utilisés par le shell.
- Relecture statique des migrations 06 à 09, y compris les prérequis, politiques RLS, fonctions `SECURITY DEFINER` et absence de clé `service_role`/mot de passe dans ces scripts.

### Ce qui n'a pas été testé

- Exécution des migrations sur une base PostgreSQL/Supabase réelle ; aucun client `psql` ni environnement PostgreSQL de test n'était connecté ici.
- Auth réelle, confirmation d'adresse e-mail, upload Storage, politiques RLS, RPC, droits admin, validation de paiement et émission de tickets sur le projet distant.
- Transfert réel MVola/Binance, paie d'enseignant/promoteur ou preuve de paiement. Les décisions financières de l'application ne constituent pas une preuve qu'un virement a été effectué.
- Test Playwright tenté, mais la navigation HTTP locale a été bloquée par l’environnement (`net::ERR_BLOCKED_BY_ADMINISTRATOR`) ; aucun parcours navigateur réel, test multi-comptes et installation sur Android/iOS ne sont donc attestés.
- Déploiement Netlify ou vérification du domaine HTTPS.

## 9. Actions requises du propriétaire avant production

1. Terminer le test Supabase actuel et relever exactement les migrations exécutées avec succès.
2. Sauvegarder la base, puis appliquer seulement les migrations 06, 07, 08 et 09 encore absentes, dans l'ordre indiqué.
3. Exécuter le diagnostic 04 et vérifier toute politique héritée ou permission Storage trop large.
4. Tester avec des comptes distincts : élève (inscription et rejet/reprise), enseignant (candidature, affectation, ressources, suivi, paie), partenaire (candidature, cotisation, ticket), promoteur (code, élève référé, commissions) et administrateur.
5. Fournir/valider les dates réelles d'année scolaire et les dates de publication des leçons ; contrôler les PE/RAPE/FRP par série avant affectation des disciplines et calendrier.
6. Confirmer le domaine HTTPS et les redirections Supabase Auth, puis publier le contenu de `site/` sur Netlify.
7. Tester l'installation PWA sur appareils réels et changer la clé/cache si une nouvelle version est déployée.
8. Décider du prestataire KYC, du cadre de confidentialité et des conditions de conservation avant tout contrôle facial.
9. Compléter « Qui sommes-nous ? » ; l’identité publique est désormais **Smart Akademia School**.

**État de cette livraison :** code et scripts préparés, contrôles statiques locaux passés. Aucune migration n'est déclarée appliquée à votre projet, aucun paiement n'est vérifié et le site n'est pas déclaré en ligne.

## 10. Scénarios de test détaillés

La recette métier complète, avec tests positifs et négatifs par rôle, est décrite dans `docs/SCENARIOS_TEST_SUPABASE_06_09.md`. Utiliser exclusivement des comptes, justificatifs et paiements fictifs sur un projet de test.

## 7. Centre de supervision et accueil du cours

La migration `09_SUPERVISION_ET_ENSEIGNANTS_COURS.sql` doit être appliquée après 01–08. Elle expose les métriques agrégées du Centre de supervision via `get_akademia_admin_supervision()`, RPC réservée à `public.is_admin()`. Le montant mensuel affiche les paiements qui ont été marqués comme approuvés dans la base (droits élèves, abonnements et contributions partenaires) ; il ne prouve pas à lui seul un encaissement externe et aucun virement n’est effectué automatiquement.

Lorsqu’un élève approuvé consulte le parcours Philosophie, le portail affiche une salutation personnalisée. Le nom du responsable est lu dans les affectations actives `teacher_subject_assignments` et ne s’affiche que si un enseignant approuvé est affecté à la série du profil. En l’absence d’affectation, l’interface l’indique au lieu d’inventer un nom. L’approbation d’une candidature enseignant et son affectation doivent être finalisées par l’administration.


## Mise à jour 10 — justificatifs requis en amont

Exécuter `supabase/migrations/10_PREUVES_AVANT_INSCRIPTION_ET_PARTENAIRE.sql` après les migrations 01 à 09, seulement si elle n'est pas déjà appliquée. Elle permet au candidat partenaire de téléverser la première preuve dans le bucket privé alors que son profil a encore le rôle `applicant`. Lorsqu'une candidature partenaire est approuvée, la cotisation de 100 000 Ar est inscrite en `pending`; l'administrateur doit ensuite examiner le justificatif dans la section des cotisations et décider séparément. Le ticket partenaire n'est donc pas émis au seul moment de l'approbation de candidature.

Le formulaire initial des enseignants/promoteurs exige photo d'identité et justificatif de diplôme. Celui des partenaires exige le justificatif de la première cotisation, le mode de paiement, l'identifiant de transaction et `FINANCEMENT`. L'administration peut ouvrir les preuves via des URL signées temporaires.

### Connexion administrateur par le formulaire commun

Le formulaire de connexion est commun à tous les rôles. Pour l'administrateur, l'identifiant saisi est `akademia`; le site le mappe vers l'adresse de compte Auth définie par `SUPABASE_CONFIG.adminEmail`. Dans la livraison actuelle, cette adresse est `julio7271@gmail.com` et doit correspondre à l'adresse inscrite dans `akademia_admin_allowlist`. L'accès au tableau de bord exige ensuite `profiles.role='admin'` et le RPC `is_admin()`. Si l'accès échoue, exécuter `supabase/diagnostics/10_DIAGNOSTIC_CONNEXION_ADMIN.sql`; ce diagnostic ne vérifie pas le mot de passe.


## 11. Correctif du formulaire d'inscription et de la connexion unique (14 novembre 2026)

- Le site n'affiche qu'un seul formulaire de connexion, avec le bouton **Se connecter** pour tous les rôles. Le profil réellement lu depuis `public.profiles` détermine la destination après l'authentification. Aucun rôle administratif n'est accordé par le seul alias saisi.
- L'administrateur saisit `akademia` dans le champ « Adresse e-mail ou identifiant ». Cet alias est mappé vers `SUPABASE_CONFIG.adminEmail`, actuellement `julio7271@gmail.com`. Si l'adresse réellement provisionnée dans Supabase Auth est différente, harmoniser cette valeur et `akademia_admin_allowlist` avec le propriétaire du projet. Ne jamais communiquer un mot de passe dans le chat ou dans le dépôt.
- Les élèves joignent photo d'identité, preuve du droit MVola de 2 000 Ar et référence de transaction avant l'appel `signUp`. Les enseignants/promoteurs joignent photo et preuve de diplôme avant `signUp`. Les partenaires joignent preuve du versement initial de 100 000 Ar, mode de paiement, référence de transaction et référence `FINANCEMENT` avant `signUp`.
- Lorsque Supabase exige la confirmation d'e-mail et n'ouvre pas de session immédiatement, les fichiers sont provisoirement gardés dans IndexedDB du navigateur courant puis téléversés après la connexion. Utiliser le même navigateur et un appareil personnel. Ce stockage local temporaire n'est pas chiffré par l'application.
- Sur une base où 01 à 09 ont déjà été appliquées, exécuter uniquement `supabase/migrations/10_PREUVES_AVANT_INSCRIPTION_ET_PARTENAIRE.sql` si elle n'est pas déjà appliquée. Ne pas rejouer les migrations précédentes.
- Si la connexion admin échoue, exécuter en lecture seule `supabase/diagnostics/10_DIAGNOSTIC_CONNEXION_ADMIN.sql`. Vérifier `AUTH_USER_ABSENT`, e-mail non confirmé, profil manquant, rôle différent de `admin` ou adresse non présente/activée dans l'allowlist. Le diagnostic ne lit jamais le mot de passe et ne peut pas confirmer qu'il est correct.


## Mise à jour v16 — champs justificatifs avant inscription professionnelle

Après remplacement de `site/index.html`, `site/role-portal.js` et `site/service-worker.js` dans GitHub, vérifiez dans le formulaire « Devenir enseignant », « Devenir promoteur » et « Devenir partenaire » que les pièces apparaissent avant « Créer mon compte candidat ». Le formulaire doit refuser la création si une pièce obligatoire manque. Cette version n'ajoute aucune migration SQL. Une actualisation forcée du navigateur peut être nécessaire; le service worker v16 renouvelle le cache PWA.
