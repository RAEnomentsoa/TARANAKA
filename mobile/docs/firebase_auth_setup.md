# Récupération du compte par e-mail (Firebase Auth)

Projet Firebase : **`taranaka-db8c0`**. L'application Android
`mg.smartsaha.taranaka` y est enregistrée par `flutterfire configure`.

## Principe

Les données de santé restent **chiffrées sur le téléphone**. Firebase sert
seulement à prouver que la personne possède l'adresse e-mail.

1. **Création du profil avec une adresse e-mail (mode personnel).**
   - L'application tire un secret aléatoire de 32 octets.
   - Ce secret protège une copie de la clé du profil. C'est le même mécanisme
     que le code de récupération.
   - L'état passe à « en attente ».
2. **Dès qu'il y a Internet** (à la création, ou à la prochaine ouverture du
   profil) :
   - un compte Firebase est créé avec un **mot de passe aléatoire** que personne
     ne connaît, donc rien à inventer ni à retenir ;
   - le secret est envoyé dans Firestore, à l'emplacement
     `recovery/{uid}/profiles/{profileId}` ;
   - le secret est effacé du téléphone et l'état passe à « active ».
3. **« Code oublié ? » → « Par e-mail ».**
   - L'application envoie l'**e-mail standard de réinitialisation Firebase**.
   - Le lien ouvre la page Firebase, où la personne choisit un mot de passe.
   - De retour dans l'appli, elle tape ce mot de passe. L'appli se connecte,
     lit le secret, retrouve la clé et demande un nouveau code secret.
   - **Les données sont conservées.**
4. **Adresse déjà utilisée** (autre profil, réinstallation) :
   - l'état devient « à confirmer » ;
   - dans Paramètres → « Récupération par e-mail », la personne reçoit le lien,
     choisit un mot de passe et le tape pour confirmer.

Le code de récupération universel (téléchargeable) reste disponible, sans
Internet et sans e-mail.

Les mauvais secrets comptent comme de mauvais codes : 5 essais, puis un
délai. Les mauvais mots de passe sont limités par Firebase
(`too-many-requests`).

## Fichiers

| Fichier | Rôle |
|---|---|
| `lib/firebase_options.dart`, `android/app/google-services.json` | Générés par `flutterfire configure` |
| `lib/core/auth/auth_service.dart` | `AuthService` : `register`, `attach`, `sendPasswordReset`, `readSecret` ; `FirebaseAuthService` |
| `lib/core/security/profile_registry.dart` | `prepareEmailRecovery`, `pendingEmailSecret`, `markEmailActive`, `markEmailToConfirm`, `recoverWithEmailSecret` |
| `lib/app/session_controller.dart` | `syncEmailRecovery`, `enableEmailRecovery`, `confirmEmailRecovery`, `sendPasswordReset`, `fetchEmailSecret`, `recoverWithEmailSecret` |
| `lib/features/profiles/presentation/email_link_form.dart` | Envoi du lien, saisie du mot de passe, messages d'erreur |
| `lib/features/profiles/presentation/forgot_pin_screen.dart` | « Par e-mail » à côté du code de récupération |
| `lib/features/settings/presentation/security_settings.dart` | Paramètres → « Récupération par e-mail » |
| `firestore.rules` | Chaque compte ne lit et n'écrit que ses propres secrets |
| `test/helpers/fake_auth.dart` | Faux service pour les tests, sans réseau |

## À faire dans la console Firebase (une seule fois)

1. **Authentication → Méthode de connexion → E-mail/Mot de passe :
   Activer.** Sinon l'erreur `operation-not-allowed` s'affiche comme « La
   récupération par e-mail n'est pas disponible pour le moment ».
2. **Firestore Database → Créer une base de données.** Choisissez le mode
   production et une région proche, par exemple `europe-west1` ou
   `africa-south1`.
3. Déployez les règles depuis le dossier `mobile` :

   ```bash
   firebase deploy --only firestore:rules --project taranaka-db8c0
   ```

4. Optionnel : dans **Authentication → Modèles → Réinitialisation du mot de
   passe**, passez la langue en français et adaptez le texte, par exemple
   « Choisissez un mot de passe, puis revenez dans TARANAKA pour le taper ».

## Hors ligne

`Firebase.initializeApp` ne fait aucun appel réseau. Firebase n'est contacté
que dans trois cas :

- la création du compte (une fois) ;
- l'envoi du lien ;
- la lecture du secret.

Chaque appel ne pèse que quelques Ko. Sans réseau, un message propose le code
de récupération.

## Confidentialité

La politique de confidentialité doit mentionner :

- l'adresse e-mail ;
- Firebase (Google) comme sous-traitant ;
- que Firestore ne contient que le secret de récupération, sans aucune donnée
  de santé.
