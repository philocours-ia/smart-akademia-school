# Mise à jour — conditions d’adhésion des enseignants

Le formulaire de création de compte enseignant affiche une rubrique « Conditions générales d’adhésion » avec le message : « Votre adhésion à la plateforme Smart Akademia School vous sanctionne d’une cotisation mensuelle de 5 000 Ar. »

Deux choix exclusifs sont proposés : « J’accepte » et « Je refuse ». La soumission du formulaire enseignant est bloquée si aucun choix n’est fait ou si la personne refuse. Le choix n’est demandé que pour le parcours enseignant ; les inscriptions partenaires et promoteurs ne sont pas modifiées.

Le module `site/teacher-adhesion-terms.js` est chargé par le service worker après l’installation de sa nouvelle version. Après le déploiement, recharger l’application en ligne afin que le nouveau service worker soit activé. Aucun changement de schéma Supabase n’est requis.
