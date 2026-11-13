# Smart Akademia School — Guide de configuration et de mise en ligne

## État réel du livrable

Ce dossier contient une version PWA installable de l'interface, le portail d'entrée d'administration séparé, un manifeste, un service worker, des icônes, le script SQL Supabase et ce guide. **Le site n'est pas encore déployé et le backend n'est pas encore relié** : aucun URL de projet Supabase, aucune clé publique, aucune adresse e-mail d'administration et aucun domaine/compte d'hébergement n'ont été fournis.

L'application ne crée plus de comptes, d'abonnements ni de progression dans le navigateur comme solution de remplacement. Tant que Supabase n'est pas configuré, les formulaires de connexion/inscription signalent que le service est indisponible. C'est intentionnel : éviter des comptes et paiements locaux non partagés et non fiables. La connexion administrateur ne peut pas être testée en direct avant de renseigner l'URL Supabase, la clé publique et l'adresse e-mail autorisée.

## Contenu du paquet

- `index.html` : application élèves ; les titres et résumés du PE sont visibles en aperçu, mais les corps complets des leçons sont chargés depuis Supabase uniquement avec un abonnement actif et une date de sortie atteinte. Le tableau de bord admin reste réservé au rôle serveur `admin`.
- `administration.html` : porte d'entrée distincte vers la connexion administrateur. Elle n'est liée depuis aucun menu élève. La confidentialité ne dépend toutefois pas du secret de l'URL : Auth Supabase et RLS protègent les actions et les données.
- `manifest.webmanifest`, `service-worker.js`, `icons/` : ressources PWA.
- `AKADEMIA_supabase_setup.sql` : script de création/mise à jour des tables, politiques RLS, stockage privé et fonctions de tickets.
- `MIGRATION_CONNEXION_ADMIN.sql` : autorisation privée et provisionnement sûr du compte administrateur ; à exécuter après le script principal.

## 1. Créer et configurer Supabase

1. Créer un projet Supabase et conserver son URL de projet et sa clé publique `anon`/publishable. **Ne jamais mettre une clé `service_role` ou `secret` dans le HTML, le manifeste ou le dépôt public.**
2. Ouvrir le SQL Editor, sauvegarder les données existantes si le projet n'est pas neuf, puis exécuter `AKADEMIA_supabase_setup.sql`.
3. Ouvrir `MIGRATION_CONNEXION_ADMIN.sql`, remplacer `VOTRE_ADRESSE_ADMIN` par l'adresse e-mail exacte de l'administrateur, puis exécuter ce script. Cette migration inscrit l'adresse dans une liste privée côté base et adapte le déclencheur d'inscription : seul cet e-mail reçoit le rôle `admin`. Les autres inscriptions restent obligées de fournir une série élève valide.
4. **Après la migration**, aller dans Authentication → Users et créer l'utilisateur avec l'adresse autorisée et un mot de passe temporaire. Le déclencheur crée automatiquement son profil `admin` avec `must_change_password = true`. Pour un compte déjà présent dans Auth, la migration le promeut également s'il correspond à l'adresse autorisée.
5. Dans Authentication → Providers, activer Email et choisir le comportement de confirmation d'adresse souhaité. Pour le compte admin, vérifier que l'adresse est confirmée avant le premier essai de connexion.
6. Dans Authentication → URL Configuration, définir la Site URL et ajouter les URL de redirection du domaine publié, notamment `https://VOTRE_DOMAINE/` et `https://VOTRE_DOMAINE/index.html` (adapter exactement le domaine).
7. Dans `index.html`, renseigner les trois valeurs de `SUPABASE_CONFIG` :

```js
const SUPABASE_CONFIG = {
  url: 'https://VOTRE-PROJET.supabase.co',
  anonKey: 'VOTRE_CLE_PUBLIQUE_ANON',
  adminEmail: 'VOTRE_ADRESSE_ADMIN'
};
```

La valeur `adminEmail` doit être identique à l'adresse ajoutée dans `MIGRATION_CONNEXION_ADMIN.sql` et au compte Auth créé. L'identifiant visible dans le portail reste `akademia` ; le mot de passe est vérifié par Supabase Auth. Le mot de passe temporaire `210917` peut être utilisé pour le premier accès si le projet accepte cette longueur, mais il doit être remplacé immédiatement par un mot de passe robuste d'au moins 12 caractères. Ne jamais inscrire le mot de passe dans le HTML, le dépôt GitHub, les scripts SQL ou les fichiers publiés.

**Contrôle de sécurité à la connexion :** après authentification, l'application lit le profil dans `public.profiles`, impose le changement du mot de passe initial, puis appelle `rpc('is_admin')` côté serveur avant d'afficher le tableau de bord. Les autorisations réelles des données restent imposées par les politiques RLS ; le contrôle JavaScript n'est qu'une vérification supplémentaire.

**Vérification dans Supabase SQL Editor :**

```sql
select
  u.email,
  (u.email_confirmed_at is not null) as email_confirme,
  u.last_sign_in_at,
  p.role,
  p.series,
  p.must_change_password,
  a.enabled as adresse_admin_autorisee
from auth.users u
left join public.profiles p on p.id = u.id
left join public.akademia_admin_allowlist a
  on a.email = lower(trim(u.email))
where lower(u.email) = lower('VOTRE_ADRESSE_ADMIN');
```

Avant le changement de mot de passe, le résultat attendu est `role = admin`, `series = Administrateur`, `must_change_password = true`, `adresse_admin_autorisee = true`. Après le changement, `must_change_password` doit devenir `false`. Le compte ne doit accéder au tableau de bord que dans ce dernier état.

## 2. Déployer le dossier sur un hébergement HTTPS

Publier uniquement les ressources nécessaires à l'interface sur un hébergement statique HTTPS (par exemple Cloudflare Pages, Netlify ou un hébergement Web classique). La racine web doit contenir `index.html`, `administration.html`, `manifest.webmanifest`, `service-worker.js` et `icons/`. Ne publiez pas le script SQL ni ce guide dans la racine publique ; conservez-les dans un emplacement privé.

Configurer ensuite Supabase Auth URL Configuration avec l'URL réelle du site, tester les liens de confirmation et de récupération de mot de passe, puis vérifier le portail administrateur.

Portes d'entrée après publication :

- Élèves : `https://VOTRE_DOMAINE/`
- Administration : `https://VOTRE_DOMAINE/administration.html` (ou `https://VOTRE_DOMAINE/index.html?espace=administration`)

L'interface élève ne contient aucun bouton ni lien d'administration. Mais l'URL dédiée n'est pas un mécanisme d'autorisation : le rôle doit rester vérifié par Supabase et chaque table/storage doit rester protégé par les politiques RLS.

## 3. Installer sur téléphone

- Android : ouvrir le site publié dans Chrome, puis menu ⋮ → « Installer l'application » ou « Ajouter à l'écran d'accueil ».
- iPhone : ouvrir le site dans Safari → Partager → « Sur l'écran d'accueil ».

Le site doit être servi en HTTPS (ou localhost pour les essais). Le navigateur doit pouvoir récupérer le manifeste et le service worker. Le manifeste est configuré avec les icônes 192×192 et 512×512, la portée racine et l'affichage standalone.

## 4. Fonctionnalités intégrées et limites

- Comptes et profils élèves : Supabase Auth + `profiles`, séries Seconde, Première L/S/OSE et Terminale L/S/OSE (les anciens profils « Première » restent reconnus à titre transitoire).
- Administrateur : login d'interface `akademia`, email Auth renseigné dans la configuration, rôle `admin` confirmé côté base, changement de mot de passe initial imposé.
- Progression : sauvegarde par élève dans `student_progress`; création/modification autorisée seulement pour les leçons déjà ouvertes par le calendrier et l’abonnement actif. Lecture de son propre suivi et lecture admin de la progression globale.
- Abonnement : 30 jours par activation. Demande accompagnée d'une preuve obligatoire (image/PDF, 700 Ko max), d'un moyen MVola/Binance Pay et de la référence fixe `AKADEMIA`. Paiement non vérifié automatiquement : le professeur doit contrôler la preuve avant validation.
- Ticket : un nouveau ticket unique est attribué par déclencheur SQL à chaque nouvelle activation validée. Il constitue un reçu d'activation, **pas un mot de passe** ; l'élève se connecte avec son e-mail et son mot de passe.
- Rappels : notification dans l'application à la connexion/consultation lorsqu'il reste 7 jours ou moins. Aucun e-mail/SMS automatique programmé ; cela demanderait une Edge Function/cron et un fournisseur e-mail/SMS.
- Citations et forum : les ajouts personnalisés et débats/commentaires sont stockés dans des tables Supabase et partagés entre les comptes. Les QCM, la bibliothèque et la banque de citations statiques restent incorporés au HTML. Les 21 corps de leçons T12 sont dans la table privée `course_lesson_content` et ne sont servis qu’après validation serveur de l’abonnement et de la date de sortie.
- PWA : le service worker met en cache le shell same-origin. Les données Supabase, l'authentification et les fonctions de paiement nécessitent Internet. Les bibliothèques externes (Tailwind, Supabase JS, polices et icônes chargées par CDN) peuvent aussi nécessiter Internet ; cette version n'est pas une application pleinement hors ligne.
- « Qui sommes-nous ? » : le texte institutionnel et l'emplacement de biographie/parcours sont présents et peuvent être complétés ultérieurement.

## 5. Référentiel PE et organisation des cours

Le PE T12 consulté organise le programme autour de quatre thématiques :

1. Caractéristiques de la philosophie.
2. Essence de l'homme.
3. Formations de la connaissance.
4. Pratiques sociales.

L'application a réorganisé les leçons déjà présentes selon ces quatre ensembles, sans inventer de nouvelle leçon. Les modules explicitement signalés « Complément AKADEMIA » sont des développements pédagogiques conservés du fichier d'origine, pas des intitulés officiels revendiqués. Les RAPE T11 L/S/OSE de septembre 2026 permettent désormais d'afficher un aperçu du parcours Première par série et sa progression en cinq périodes. Le détail des cours T11, exercices et dates de publication n'est pas encore importé. Le RAPE T10 consulté ne répertorie pas la philosophie en Seconde ; l'application n'y invente donc pas de cours de philosophie.

Le document PE consulté porte la mention « version expérimentale ». Les RAPE T12 de septembre 2026 indiquent Philosophie : L = 5 h/semaine, S = 3 h/semaine, OSE = 3 h/semaine. Pour T11, le PE détaillé indique L = 3 h, S = 2 h et OSE = 2 h/semaine, alors que les trois RAPE T11 indiquent 3 h/semaine. L'application présente les écarts au lieu de les résoudre arbitrairement.

Références documentaires consultées :
- Portail documentaire du Ministère de l'Éducation nationale : https://plateforme.education.mg/bibliotheque-numerique/
- FRP Philosophie T12, L/S/OSE, édition octobre 2026 : https://plateforme.education.mg/bibliotheque-numerique/theme/biblio/pix/frp/FRP_philo_T12_L_S_OSE.pdf
- Copie consultée du PE T12 (identifiée dans le document comme version expérimentale) : https://www.hrdaniel.mg/pe-pdf/T12.pdf

## 6. Verrouillage des cours et répartition annuelle (nouvelle règle)

- Après inscription, l’élève peut ouvrir son espace et consulter l’état de son compte, mais les cours complets sont verrouillés tant qu’il n’a pas d’abonnement actif validé.
- Le paiement ne débloque pas automatiquement toutes les leçons : une leçon est accessible seulement si `subscriptions.status = 'actif'`, `expires_at > now()` et si une ligne de `course_release_schedule` correspond à la série de l’élève et à une date `release_at <= now()`.
- Les corps des 21 leçons existantes ont été retirés du HTML public et migrés dans `course_lesson_content`. La politique RLS Supabase ne renvoie à l’élève que les leçons ouvertes. Les titres et résumés restent visibles comme aperçu du programme.
- `course_release_schedule` est volontairement créée sans dates de publication. Aucun cours complet n’est accessible avant la validation des contenus et des dates pour la série concernée. Les RAPE T10, T11 et T12 sont désormais repérées ; les semaines ne sont pas converties automatiquement en dates calendaires.
- La colonne `release_at` est un horodatage avec fuseau horaire. Les périodes de RAPE (semaines 1–7, 8–14, 15–21, 22–27 et 28–33) doivent être rapprochées du calendrier scolaire officiel avant saisie des dates. Aucune date n’est inventée.
- Après réception du document annuel, le script de mise à jour ajoutera une ligne par leçon et par série dans `course_release_schedule`. Les leçons futures resteront verrouillées ; elles seront déverrouillées automatiquement dès leur date et heure prévues, si l’abonnement de l’élève est toujours actif.

Exemple de structure (à ne pas exécuter avec ces dates fictives) :

```sql
insert into public.course_release_schedule (series, lesson_id, release_at, release_note)
values ('Terminale L', 't1c1', 'AAAA-MM-JJ 00:00:00+03', 'Période du programme');
```

**Action pédagogique restante :** confirmer les différences de volumes PE/RAPE pour Première S et OSE, importer/rédiger et valider les leçons T11, puis fixer les dates de publication des leçons à partir du calendrier scolaire officiel.

## 7. Vérifications faites et vérifications restantes

Vérifications possibles localement : cohérence des fichiers HTML/JS, présence des ressources PWA, validation de la syntaxe JavaScript et des références locales, vérification visuelle des parcours avec backend non configuré.

Impossible avant de recevoir les paramètres du propriétaire : création réelle du compte admin, authentification Supabase, validation réelle des politiques RLS et storage, confirmations e-mail, tests des téléversements privés, tickets en base, tests des leçons verrouillées/déverrouillées sur un projet connecté et toute publication sur un domaine. Le calendrier de sortie des leçons reste vide en attendant la validation des contenus et la conversion pédagogique des semaines RAPE en dates du calendrier scolaire. Aucun paiement ne peut être vérifié automatiquement depuis MVola/Binance par le simple HTML.

Avant ouverture au public, tester dans votre propre projet : création d'un compte élève, confirmation d'e-mail, connexion, progression, dépôt d'une preuve, validation de l'abonnement par le compte admin, émission du ticket, refus d'accès d'un élève aux profils/autres preuves/autres progressions, mot de passe oublié, première connexion admin et changement du mot de passe initial.


## 8. Changement de marque et ajout de la classe de Seconde

- Le nom visible de la plateforme est désormais **Smart Akademia School**. Le code de référence de paiement reste exactement `AKADEMIA`, conformément à la consigne du propriétaire.
- Le formulaire d'inscription exige un choix explicite parmi Seconde, Première L, Première S, Première OSE, Terminale L, Terminale S ou Terminale OSE ; aucune classe n'est présélectionnée.
- La classe choisie est stockée dans le profil Supabase et ne peut pas être changée librement depuis le navigateur. Les demandes de paiement et les messages doivent correspondre à cette classe côté base.
- La Seconde est ajoutée à la structure technique et à la navigation de présentation, mais son programme, ses contenus, ses horaires et son calendrier de publication ne sont pas inventés. Le portail affiche « parcours en préparation » tant que les sources pédagogiques ne sont pas intégrées.
- **Limite documentaire :** la bibliothèque de fichiers de cette conversation n'est pas accessible à l'outil de traitement. Les documents que le propriétaire indique avoir déposés dans sa bibliothèque n'ont donc pas pu être lus. Pour reconstituer fidèlement les cours et leur répartition selon la Répartition Annuelle de Programme d'Enseignement, il faut joindre ces documents directement à la conversation (PDF, DOCX, XLSX ou images lisibles).


### Base Supabase déjà créée ?

Si votre projet Supabase a déjà reçu un ancien script, exécutez `MIGRATION_CLASSE_SECONDE.sql` dans SQL Editor au lieu de recréer les tables. Cette migration autorise la classe Seconde, enlève la valeur de classe par défaut et protège les profils contre la modification de leur classe par le navigateur. Sur un nouveau projet, utilisez le script de configuration complet.


## 9. Mise à niveau PE/RAPE (novembre 2026)

- Les parcours de Première sont désormais différenciés en **Première L, Première S et Première OSE** à l'inscription. Les anciens profils portant seulement « Première » restent conservés en base et doivent être vérifiés manuellement avant affectation à une série. Exécuter `MIGRATION_T11_PROGRAMMES_ET_SERIES.sql` dans Supabase avant d'ouvrir les nouvelles inscriptions si le backend existait déjà.
- Le module Cours affiche une structure de programme T11 issue du PE (deux thèmes) et sa progression en cinq périodes issue des RAPE de septembre 2026. L'aperçu ne prétend pas être un cours complet : les contenus, exercices et dates calendaires restent à rédiger/importer/valider.
- Les volumes horaires Première S/OSE divergent entre PE et RAPE ; l'interface expose explicitement les deux informations. Première L est concordante. Les RAPE T12 consultés indiquent 5 h/semaine en L et 3 h/semaine en S/OSE. Le RAPE T10 consulté ne répertorie pas la philosophie parmi les disciplines.
- Le RAPE fournit une progression par semaines et cinq périodes, mais pas de dates calendaires. Ne remplissez `course_release_schedule.release_at` qu'après rapprochement avec le calendrier scolaire officiel et validation pédagogique.
- Boky Citation retrouve les 40 entrées historiques et incorpore les entrées du FRP Philosophie T12 L/S/OSE. Les nouvelles citations affichent leur page imprimée, la référence RES et le lien vers le fascicule. Les libellés d'auteur sont conservés tels qu'imprimés et ne sont pas présentés comme vérifiés indépendamment.
- `REFERENTIEL_SOURCES_MEN.md` récapitule les sources officielles, les décisions d'intégration et les divergences repérées.

**Important :** cette mise à niveau prépare les fichiers et le SQL ; elle ne modifie pas un projet Supabase distant et ne publie pas l'application. La migration SQL doit être exécutée sur le projet actif, puis les fichiers web mis à jour doivent être déployés sur l'hébergement HTTPS.
