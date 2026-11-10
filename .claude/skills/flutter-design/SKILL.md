---
name: flutter-design
description: Applique des règles de design Flutter modernes, accessibles et légères pour les écrans de l'application mobile TARANAKA.
---

# Design Flutter pour TARANAKA

## Priorités
Sécurité et clarté, puis rapidité, accessibilité, performance et esthétique.

## Fondations
- Utiliser Material 3 avec un `ThemeData` central et des tokens de couleur, d'espacement et de texte.
- Ne pas coder en dur les couleurs, tailles ou textes dans les widgets.
- Utiliser une seule couleur d'accent et une police système ou une seule police embarquée légère.
- Prévoir les thèmes clair et sombre seulement s'ils restent lisibles et testés.

## Lisibilité et faible littératie
- Associer pictogramme, texte court, chiffre et audio sur les écrans clés.
- Prévoir un bouton audio en malagasy là où la spécification le demande.
- Ne jamais transmettre une information par la couleur seule.
- Écrire des phrases courtes et concrètes.

## Ergonomie
- Atteindre l'action la plus fréquente en 3 taps maximum.
- Donner une seule action principale à chaque écran.
- Garder des zones tactiles d'au moins 48 dp.
- Rendre les erreurs claires et proposer la correction.
- Demander confirmation avant toute action irréversible.
- Afficher l'état de synchronisation avec une icône et un libellé.
- Ne jamais bloquer une action principale à cause du réseau.

## Alertes
- Les alertes rouges doivent s'ouvrir immédiatement, en plein écran et hors ligne.
- Ne pas retarder une alerte avec une animation.
- Toujours afficher l'action à faire et « Cette alerte ne remplace pas un diagnostic ».

## Responsive et accessibilité
- Tester à partir de 320 dp de large, sur écran 5", avec un texte agrandi à 200 %.
- Éviter toute largeur ou hauteur fixe qui coupe le texte.
- Respecter le contraste AA, ajouter des labels `Semantics` et tester avec TalkBack.
- Vérifier les textes français et malagasy, qui peuvent être plus longs.

## Performance
- Cibler Android 8+, 1 Go de RAM et un APK de moins de 30 Mo.
- Préférer les `const` widgets et `ListView.builder`.
- Compresser les images et préférer les icônes vectorielles légères.
- Éviter les flous, les grosses ombres, les vidéos et les animations continues.
- Limiter les transitions à 150–250 ms et respecter `MediaQuery.disableAnimations`.

## À éviter
- Dégradés décoratifs, effets de verre et cartes dans des cartes
- Grands carrousels d'accueil et fausses données
- Texte sensible dans les notifications du mode discret
- Icônes sans libellé pour les actions importantes

## Vérification finale
- [ ] L'écran fonctionne en mode avion.
- [ ] Les états chargement, vide, erreur et synchronisation sont gérés.
- [ ] Aucun texte n'est codé en dur.
- [ ] Les textes restent lisibles à 200 %.
- [ ] L'écran reste fluide sur un téléphone d'entrée de gamme.