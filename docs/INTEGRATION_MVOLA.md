# Intégration MVola Merchant Pay — Smart Akademia School

Cette livraison ajoute un flux serveur pour les abonnements **élèves approuvés : 15 000 Ar / 30 jours**. Le bénéficiaire ne peut pas être crédité depuis le navigateur et aucun secret MVola n'est inclus dans Git.

## Architecture et limites

- `supabase/functions/mvola-payments/index.ts` : authentifie l'utilisateur, crée une demande à montant fixe, initie Merchant Pay et interroge le statut MVola côté serveur.
- `supabase/migrations/14_MVOLA_MERCHANT_PAYMENTS.sql` : registre privé des demandes, idempotence et règlement atomique avec création de l'abonnement après confirmation.
- La réussite n'est pas déduite de l'écran du téléphone : seul le statut interrogé auprès de MVola avec vérification référence, montant et devise déclenche l'abonnement.
- La migration 14 ne prend pas en charge les frais d'inscription de 2 000 Ar, les cotisations partenaires, Binance Pay ou l'abonnement annuel. L'abonnement annuel exige une date réelle de fin d'année scolaire ; ne pas la deviner.
- La fonction interroge le statut à la demande (polling). Aucun webhook MVola n'est activé, car l'URL et la signature/validation de callback doivent être confirmées avec le compte marchand et le contrat du propriétaire.
- Les paramètres et schémas MVola peuvent varier selon l'environnement/compte. Les chemins API sont configurables ; confirmer les champs, en-têtes et endpoint de statut dans le portail/document fourni par MVola avant production.

## Prérequis et déploiement

1. Sauvegarder la base. Vérifier que les migrations 01–08 sont appliquées, notamment la table `subscriptions`, la contrainte de formule de migration 08 et le trigger qui émet le ticket d'accès.
2. Appliquer **une seule fois** `supabase/migrations/14_MVOLA_MERCHANT_PAYMENTS.sql` dans SQL Editor ou via votre processus habituel de migration.
3. Déployer l'Edge Function :

   ```sh
   supabase functions deploy mvola-payments
   ```

   La fonction doit conserver la vérification JWT activée (valeur par défaut de Supabase). Ne pas utiliser `--no-verify-jwt`.
4. Ajouter les secrets depuis le terminal sécurisé, sans les committer :

   ```sh
   supabase secrets set \
     MVOLA_API_BASE_URL=https://devapi.mvola.mg \
     MVOLA_CONSUMER_KEY='clé-sandbox' \
     MVOLA_CONSUMER_SECRET='secret-sandbox' \
     MVOLA_PARTNER_NAME='Smart Akademia School' \
     MVOLA_PARTNER_MSISDN='034XXXXXXX' \
     APP_ORIGIN='https://votre-domaine.example'
   ```

   Variables facultatives pour adapter les routes exactement à votre contrat MVola :

   ```sh
   supabase secrets set \
     MVOLA_TOKEN_PATH=/token \
     MVOLA_PAYMENT_PATH=/merchantpay/1.0.0/transactions/type/merchantpay \
     MVOLA_STATUS_PATH='/merchantpay/1.0.0/transactions/{id}'
   ```

   Le déploiement production doit utiliser le domaine et les identifiants de production communiqués par MVola, jamais les identifiants Sandbox. `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont fournis dans l'environnement des Edge Functions Supabase. Si votre projet n'injecte pas ces variables, les configurer comme secrets du projet avec les valeurs Supabase correspondantes. Le service-role est exclusivement serveur.

## Contrat HTTP de la fonction

Appeler `mvola-payments` avec une session Supabase Auth valide et JSON. Le navigateur doit envoyer son access token via `Authorization: Bearer ...`; ne jamais envoyer la service-role key.

Créer un paiement mensuel :

```json
{
  "action": "initiate",
  "payerMsisdn": "0341234567",
  "idempotencyKey": "UUID-généré-une-fois-pour-cette-intention"
}
```

La référence, l'utilisateur, le tarif (15 000 Ar), la devise et la formule sont établis côté serveur. Réutiliser la même clé UUID pour les nouvelles tentatives réseau liées au même bouton, et en générer une nouvelle pour un paiement volontairement distinct.

Interroger ensuite le statut :

```json
{
  "action": "status",
  "paymentId": "UUID-retourné-par-initiate"
}
```

Réponse : `pending`, `paid`, `failed` ou `cancelled`. Le client peut réinterroger avec temporisation ; ne pas appeler en boucle rapide. Un abonnement actif et son ticket sont créés par la base uniquement après une réponse MVola terminale réussie avec montant, devise, référence externe et identifiant financier cohérents.

Exemple d'appel depuis un client Supabase déjà initialisé :

```js
const { data, error } = await supabaseClient.functions.invoke('mvola-payments', {
  body: { action: 'initiate', payerMsisdn, idempotencyKey }
});
if (error) throw error;
// Conserver data.paymentId puis appeler l'action status après confirmation sur le téléphone.
```

## Avant toute activation en production

- Faire valider les routes et structures exactes des requêtes/réponses avec la documentation officielle attachée au compte marchand MVola. La documentation accessible publiquement peut différer de l'offre activée pour le compte.
- Tester en Sandbox : token, paiement accepté/refusé/expiré, réponse de statut et répétition de requêtes.
- Faire une revue de migration sur une base de recette. En particulier, le chemin `mvola-confirmed://...` est un marqueur interne associé à un règlement API, pas un fichier téléversé ; les fonctions d'activation manuelle qui exigent un reçu Storage ne sont pas utilisées par ce nouveau flux.
- Vérifier les logs Supabase et MVola, limites d'appels et politique de conservation avant mise en production.
- Le formulaire actuel de `site/index.html` utilise encore le parcours de justificatif manuel. La fonction backend est prête et son contrat client est documenté ; le bouton / l'écran de paiement doit être raccordé à l'interface et testé avec les identifiants Sandbox du propriétaire avant d'afficher ce nouveau parcours aux utilisateurs. Ne pas annoncer ce flux comme disponible aux élèves avant ce raccordement et les tests.
