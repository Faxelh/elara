# Elara

Lecteur vidéo et audio pour iPhone, entièrement en français (SwiftUI, iOS 17+).

## Étape 1 (cette version)
- 4 onglets : Accueil, Transfert, Compresser, Réglages
- Import de vidéos depuis **Photos** et de vidéos/musiques depuis **Fichiers**
- Les fichiers déposés dans le dossier « Elara » de l'app Fichiers apparaissent aussi (tirer vers le bas pour actualiser)
- Lecteur vidéo natif : AirPlay, image dans l'image
- Lecteur audio : lecture en arrière-plan, commandes sur l'écran verrouillé
- Lecture automatique (arrêter, répéter, suivant, boucle, retour à la liste) et reprise de la lecture
- Historique, vider le cache, noter l'app, à propos
- Renommer, partager, supprimer (appui long sur un média)

## Étape 2
- **Dossier privé** protégé par Face ID (ou Touch ID / code de l'iPhone)
- Les médias privés sont invisibles dans l'accueil, l'historique et l'app Fichiers, et chiffrés quand l'iPhone est verrouillé
- « Déplacer vers Privé » par appui long sur un média, ou import direct dans le dossier privé
- Verrouillage automatique quand on quitte l'app, contenu masqué dans le sélecteur d'apps

Formats : mp4, mov, m4v, 3gp, mp3, m4a, aac, wav, aiff, caf, flac.

## Mettre le projet sur GitHub (depuis Windows)

1. Créez un dépôt vide nommé `elara` sur github.com (sans README).
2. Dézippez ce dossier, ouvrez-le dans VS Code, puis dans le terminal (Ctrl + `) :

```bash
git init
git add .
git commit -m "Elara - étape 1"
git branch -M main
git remote add origin https://github.com/VOTRE-COMPTE/elara.git
git push -u origin main
```

## Compiler avec Codemagic (sans compte Apple)

1. Sur codemagic.io : **Add application** → GitHub → choisissez `elara`.
2. Type de projet : **iOS App**, configuration : **codemagic.yaml**.
3. Lancez **Start new build** → workflow **« Elara – Vérification »**.
4. Si le build est vert, le code compile. Ensuite, chaque `git push` relance la vérification.

## Plus tard : TestFlight (avec le compte Apple Developer)

1. Dans App Store Connect : créez l'app avec l'identifiant `com.kounandi.elara`.
2. Créez une clé API (Utilisateurs et accès → Intégrations) et ajoutez-la dans Codemagic
   (Teams → Integrations → App Store Connect) sous le nom **Elara ASC**.
3. Lancez le workflow **« Elara – Envoi sur TestFlight »**.

Le projet Xcode est généré automatiquement par XcodeGen à partir de `project.yml`.
