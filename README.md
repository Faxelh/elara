# Elara 🎬🎵

**Elara** est une application **iPhone et Android** tout-en-un pour lire, organiser et protéger vos vidéos et votre musique, pensée en français.

## ✨ Fonctionnalités

- 🎬 **Lecteur vidéo** : lisez les vidéos de l'app Photos et de l'app Fichiers
- 🎵 **Lecteur audio** : écoutez votre musique avec une interface simple
- 🔒 **Dossier privé** : vos fichiers sensibles protégés par Face ID (iPhone) ou par code, schéma, empreinte ou visage (Android)
- 🗜️ **Compression vidéo** : réduisez la taille de vos vidéos
- 📶 **Transfert Wi‑Fi** : envoyez des fichiers depuis votre ordinateur vers l'app
- ⬇️ **Téléchargeur intégré** : récupérez des fichiers directement dans l'app

## 🌍 Langues

Français · English · Русский · Español

## 📲 Installation

> Application en cours de développement. Elle n'est pas sur l'App Store ni sur le Play Store : on l'installe soi-même avec un fichier d'installation, à télécharger dans les [**Releases**](https://github.com/Faxelh/elara/releases) du dépôt.

### 🤖 Android

1. Sur votre téléphone, ouvrez la page [**Releases**](https://github.com/Faxelh/elara/releases) et téléchargez le fichier **`.apk`** de la dernière version.
2. Ouvrez le fichier téléchargé (depuis la notification ou l'app *Fichiers*).
3. Si Android demande une autorisation, activez **« Autoriser depuis cette source »** pour votre navigateur ou votre gestionnaire de fichiers, puis revenez en arrière.
4. Touchez **Installer**. Si Play Protect affiche un avertissement, choisissez **« Installer quand même »**.
5. Ouvrez **Elara** : c'est prêt.

### 🍎 iPhone

Il faut un ordinateur (Windows ou Mac) pour la première installation, avec **Sideloadly**.

1. Téléchargez le fichier **`.ipa`** de la dernière version dans les [**Releases**](https://github.com/Faxelh/elara/releases).
2. Installez [**Sideloadly**](https://sideloadly.io/) sur votre ordinateur.
   *Sous Windows, installez aussi iTunes et iCloud depuis le site d'Apple (pas depuis le Microsoft Store).*
3. Branchez votre iPhone avec un câble et touchez **Se fier** sur l'iPhone si la question s'affiche.
4. Ouvrez Sideloadly, glissez le fichier `.ipa` dans la fenêtre et saisissez votre identifiant Apple.
5. Cliquez sur **Start** et attendez la fin de l'installation.
6. Sur l'iPhone, allez dans **Réglages › Général › VPN et gestion de l'appareil**, touchez votre identifiant Apple puis **Faire confiance**.
7. Sur iOS 16 ou plus récent, activez aussi **Réglages › Confidentialité et sécurité › Mode développeur**, puis redémarrez l'iPhone.
8. Ouvrez **Elara**.

> ⚠️ Avec un identifiant Apple gratuit, l'app expire au bout de **7 jours** : il faut la réinstaller avec Sideloadly. Pour éviter cela, utilisez **SideStore** ou **AltStore**, qui renouvellent l'app automatiquement.

## 🛠️ Technologies

- **Swift / SwiftUI** : application iPhone native
- **Codemagic** : compilation de l'app iPhone sans Mac
- **GitHub Actions** : compilation automatique
- **Git / GitHub** : suivi du code

## 🗺️ Feuille de route

- [x] Lecteur vidéo
- [x] Dossier privé
- [x] Lecteur audio complet
- [x] Compression vidéo
- [x] Transfert Wi‑Fi
- [x] Version Android (APK) avec dossier privé
- [ ] Publication sur l'App Store

## 📁 Structure du dépôt

```
├── Elara/              Application iPhone
├── android/            Application Android
├── scripts/            Scripts utilitaires
├── .github/workflows/  Compilation automatique
├── codemagic.yaml      Configuration Codemagic
├── project.yml         Configuration du projet iPhone
└── VERSION             Numéro de version
```

## 👤 Auteur
Créé par **Faxel Kwadio** — [@Faxelh](https://github.com/Faxelh)
Développeur autodidacte, je crée des applications utiles pour mon quotidien et celui des autres.

## 🚀 Mes projets
| Projet | Description |
|---|---|
| [**Faxel**](https://github.com/Faxelh/Faxel) | Application iPhone et Android : navigateur avec téléchargement intégré, lecteur vidéo/audio, bibliothèque |
| [**Music**](https://github.com/Faxelh/Music) | Lecteur de musique iPhone et Android : bibliothèque, égaliseur, paroles, playlists, mix automatiques |

## 🛠️ Technologies
![Swift](https://img.shields.io/badge/Swift-FA7343?style=flat&logo=swift&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![Django](https://img.shields.io/badge/Django-092E20?style=flat&logo=django&logoColor=white)
![Git](https://img.shields.io/badge/Git-F05032?style=flat&logo=git&logoColor=white)
![VS Code](https://img.shields.io/badge/VS_Code-007ACC?style=flat&logo=visualstudiocode&logoColor=white)
