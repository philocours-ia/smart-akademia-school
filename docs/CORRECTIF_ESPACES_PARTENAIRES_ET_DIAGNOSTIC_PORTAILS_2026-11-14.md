# Correctif — espace partenaire et diagnostic des portails

## Ce qui a été corrigé

- L'espace partenaire charge désormais indépendamment le statut de membre, l'historique des cotisations et la candidature initiale. Une erreur RLS/table/storage dans un bloc ne masque plus les autres cartes.
- Le tableau de bord affiche le nom du partenaire ou de l'organisme, l'état de la candidature, les engagements, le statut du ticket, les paiements, les références et les liens signés temporaires vers les justificatifs privés.
- Si la preuve de la première cotisation jointe à la candidature ne figure pas dans `partner_contributions`, l'espace l'affiche et indique explicitement de ne pas payer une seconde fois. L'administration doit vérifier la migration 10 et le rapprochement de la ligne.
- Un paiement mensuel déjà en attente bloque l'envoi d'un doublon depuis le portail.
- Un chargement d'espace qui échoue affiche maintenant un message explicite, son erreur technique et un bouton Réessayer au lieu de laisser indéfiniment « Chargement sécurisé… ».
- La notice générique ne prétend plus automatiquement que la migration 06 manque : elle distingue une erreur de table, RPC, RLS ou stockage.
- Le cache PWA passe en v15 et `role-portal.js` reçoit un en-tête `Cache-Control: no-cache` pour que le correctif remplace le script ancien.

## Audit des autres portails dans les sources

- `applicant` : consulte son dossier de candidature, son statut et sa note de décision.
- `teacher` : charge affectations, agenda, progression, ressources, finance et demandes administratives. Une requête défaillante était auparavant susceptible de remplacer tout l'espace par une notice générique ; le nouveau message donne le détail et permet une nouvelle tentative.
- `promoter` : charge les commissions, demandes financières et referrals ; un échec était auparavant susceptible de masquer l'ensemble du portail ; le message d'erreur est maintenant exploitable.
- `student` en attente : consulte son dossier d'inscription et son statut. Les élèves approuvés sont dirigés vers l'application élève principale.

## Point Supabase important pour les partenaires

La migration 10 déjà présente dans le projet autorise le candidat partenaire à téléverser la preuve initiale alors que son rôle est encore `applicant`. Lorsqu'une candidature partenaire est approuvée par `admin_review_role_application`, cette fonction crée une ligne `partner_contributions` en attente avec le montant 100 000 Ar, la référence `FINANCEMENT` et la preuve privée. La validation ultérieure de cette cotisation par `admin_decide_partner_contribution` crée le ticket et active la période mensuelle.

Si migration 10 n'a pas été exécutée, le partenaire peut avoir une candidature approuvée sans ligne de cotisation initiale. Le portail l'explique et évite de demander un second versement. Vérifier l'état de la migration avant toute intervention ; ne pas réexécuter les migrations 01 à 09.

## Déploiement

1. Remplacer `site/role-portal.js`, `site/service-worker.js` et `site/_headers` dans le dépôt GitHub.
2. Commit et push sur la branche connectée à Netlify.
3. Attendre le déploiement publié.
4. Sur le téléphone/navigateur : fermer l'application PWA, ouvrir le domaine en navigation privée ou faire un rechargement forcé. Le cache v15 se mettra à jour.
5. Tester les portails Partenaire, Enseignant, Promoteur et Candidat avec des comptes de test.

## Limites de vérification

Les sources ont été examinées et le JavaScript soumis au contrôle syntaxique local. Aucun accès au projet Supabase réel n'est disponible dans cet environnement : les tables, données, fonctions RPC, policies RLS, buckets et sessions du site en ligne ne peuvent pas être vérifiés ici. Le correctif n'a pas été publié lui-même.
