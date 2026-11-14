# État de préparation — 14 novembre 2026

## Décision

Le paquet est prêt pour une phase de recette propriétaire, pas pour une ouverture publique immédiate. Les fichiers ont été examinés avant modification. Aucune action n'a été effectuée sur le projet Supabase distant ni sur un hébergement.

## Fichiers source examinés

- `site/index.html` (309 904 octets dans l'archive source initiale)
- `site/administration.html`
- `site/manifest.webmanifest`
- `site/service-worker.js`
- `supabase/01_AKADEMIA_supabase_setup.sql`
- `supabase/migrations/02_MIGRATION_CONNEXION_ADMIN.sql`
- `docs/GUIDE_DEPLOIEMENT.md`
- `docs/VERIFICATION_CONNEXION_ADMIN.md`
- `docs/REFERENTIEL_SOURCES_MEN.md`
- `README.md`
- les ressources du logo et les icônes PWA

L'archive source initiale contient également les exports Boky Citation CSV/JSON et les ressources documentaires du projet.

## État fonctionnel observé dans les fichiers

| Domaine | État du code | Réserve |
|---|---|---|
| Porte élève | Présente | Auth Supabase réel non testé |
| Porte administration | Page distincte `/administration.html` | URL non secrète ; RLS reste la barrière réelle |
| Lien admin visible chez l'élève | Aucun dans nav/header/footer analysés | Vérifier visuellement après déploiement |
| Auth admin | Supabase Auth + rôle `admin` + `is_admin()` | Le mot de passe initial doit être saisi dans Auth par le propriétaire |
| Changement du mot de passe | Flag serveur + trigger sur le hash Auth | Trigger distant non testé |
| Séries | Seconde, Première L/S/OSE, Terminale L/S/OSE | Les anciens profils « Première » doivent être affectés manuellement |
| Progression | Stockage Supabase et contrôle par leçon | Suivi détaillé T11 incomplet |
| Abonnement | 30 jours, validation manuelle | Aucun paiement automatique |
| Preuve de paiement | Bucket privé, image/PDF, 700 Ko | Migration 03 à appliquer si absente |
| Ticket | Génération SQL à l'activation | Non testé sur le projet distant |
| Rappel | Dans l'application à 7 jours ou moins | Pas d'e-mail/SMS automatique |
| PWA | Manifeste, icônes, service worker | Installation à tester sur HTTPS |
| Qui sommes-nous ? | Rubrique existante | Biographie à compléter |

## Contrôles statiques effectués

- Les scripts JavaScript inline passent `node --check`.
- Le service worker passe `node --check`.
- `manifest.webmanifest` est un JSON valide.
- Les icônes sont présentes et ont les dimensions 192×192, 512×512, 180×180 et 32×32.
- Les ressources du manifeste et du service worker existent.
- Aucun bouton ou lien administrateur n'est présent dans les menus, l'en-tête ou le pied de page élève.
- Les séries proposées à l'inscription concordent avec les valeurs prévues dans le schéma SQL.
- Les moyens de paiement et la référence `AKADEMIA` concordent entre l'interface et le schéma.

## Vérifications non réalisées

- Pas de connexion réelle à Supabase : le réseau sortant de l'environnement de préparation n'a pas permis d'atteindre le projet.
- Pas de validation des migrations sur une instance PostgreSQL de test.
- Pas de test réel de l'authentification, des triggers, des politiques RLS, de Storage ou des tickets.
- Pas de validation d'un paiement réel.
- Pas de test visuel automatisé : Chromium a bloqué la navigation locale avec `ERR_BLOCKED_BY_ADMINISTRATOR`.
- Pas de déploiement ni d'installation PWA sur téléphone.

## PE / RAPE : prudence pédagogique

- Le code prévoit 21 contenus T12 dans le script SQL, destinés aux séries L/S/OSE.
- Le suivi de progression utilise quatre axes internes ; la structure de présentation des contenus conserve les cinq ensembles présents dans les données pédagogiques existantes. Le regroupement de la « Condition humaine » avec « Essence de l'homme » dans le suivi est un choix de classement interne à confirmer avec la version définitive du PE.
- L'aperçu T11 n'est pas un cours complet. Les heures PE/RAPE divergentes pour S et OSE sont conservées sans arbitrage.
- Les RAPE T11 L/S/OSE sont des documents distincts, mais le résumé de périodes affiché est partagé entre séries. Une vérification ligne par ligne de chaque PDF est nécessaire avant de figer l'affectation.
- Le calendrier `course_release_schedule` est volontairement sans date. Aucun déverrouillage complet n'est prévu tant que les dates officielles/pédagogiques ne sont pas approuvées.

## Dépendances du propriétaire

1. Identité publique confirmée : **Smart Akademia School**. Le nom est désormais harmonisé dans l’application et dans la documentation actualisée.
2. Définir ou réinitialiser le mot de passe initial directement dans Supabase Auth, confirmer l'adresse administrateur et le remplacer dès la première connexion.
3. Appliquer `03_HARDEN_PAYMENT_PROOFS.sql` si elle n'est pas déjà appliquée.
4. Exécuter `04_PRE_LAUNCH_CHECKS.sql` et corriger toute politique Storage/RLS héritée trop permissive.
5. Définir le domaine et l'hébergement HTTPS, puis configurer les URL Supabase Auth.
6. Faire valider les contenus T11 et les dates de sortie T12.
7. Effectuer les essais réels sur comptes de test et appareils mobiles.

Le site reste hors ligne tant qu'un déploiement réel n'a pas été effectué et vérifié.
