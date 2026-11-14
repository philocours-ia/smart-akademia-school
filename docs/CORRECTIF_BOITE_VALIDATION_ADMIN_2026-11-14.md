# Correctif — boîte de validation administrative

## Changements
- Regroupement visible dès le haut du tableau de bord des inscriptions élèves, candidatures professionnelles et cotisations partenaires en attente.
- Compteurs de demandes et bouton d’actualisation.
- Dossiers élèves détaillés : identité, e-mail, téléphone, série, données de paiement, date de dépôt et liens signés vers photo et preuve MVola.
- Approbation élève proposée uniquement lorsque le dossier existe et que les deux justificatifs privés sont consultables. La RPC Supabase garde le contrôle final.
- Candidatures professionnelles détaillées : rôle demandé, identité, e-mail, téléphone, spécialité, diplôme, organisme, date, preuve(s) et métadonnées de paiement partenaire.
- Historique des candidatures et cotisations déjà traitées.
- Chargement des modules administratifs isolé : une erreur dans une table secondaire n’efface plus la liste des candidatures.
- Cache PWA incrémenté pour forcer le chargement de la nouvelle interface.

## Installation
Publier le contenu Netlify à la racine du répertoire publié `site` (ou pousser le dossier source complet dans GitHub si Netlify publie `site`). Aucun SQL supplémentaire n’est requis par ce correctif d’interface si les migrations 05, 06, 07 et 10 sont déjà appliquées.

## Sécurité
Les décisions restent effectuées par les RPC existantes protégées par `public.is_admin()`. Les pièces privées sont exposées uniquement par URL signée temporaire. Ne jamais remplacer ce contrôle serveur par un simple bouton ou un masquage HTML.
