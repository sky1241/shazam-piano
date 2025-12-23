# 🎮 Google Play Console - Setup Complet ShazaPiano

**Guide pas-à-pas pour configurer ShazaPiano sur Google Play Console**

Tu es déjà inscrit ✅ → Ce guide t'amène jusqu'au lancement !

---

## 📱 PARTIE 1 : CRÉER L'APPLICATION

### Étape 1.1 : Créer une Nouvelle App

1. **Aller sur** : https://play.google.com/console/
2. **Connexion** avec ton compte Google
3. **Cliquer** : "Créer une application" (gros bouton bleu en haut à droite)

### Étape 1.2 : Formulaire Création

**Détails de l'application** :

```
Nom de l'application : ShazaPiano
Langue par défaut : Français (France)
```

**Type d'application** :
```
☑️ Application
☐ Jeu
```

**Gratuite ou payante** :
```
☑️ Gratuite
```

**Déclarations** :
```
☑️ Je confirme que cette application respecte les Règles relatives au contenu pour les développeurs Google Play et la législation américaine sur le contrôle des exportations.
```

4. **Cliquer** : "Créer une application"

---

## 🆔 PARTIE 2 : CONFIGURER L'IDENTITÉ

### Étape 2.1 : Fiche Play Store

**Navigation** : Présence sur Google Play > Fiche du Play Store principale

#### Titre de l'application
```
Nom : ShazaPiano
Nom court : ShazaPiano
```

#### Description

**Description courte** (80 caractères max) :
```
Transforme ton piano en 4 vidéos pédagogiques animées ! 🎹
```

**Description complète** (4000 caractères max) :
```
🎹 ShazaPiano - Ton Prof de Piano IA

Enregistre quelques secondes de piano et obtiens instantanément 4 vidéos de clavier animé adaptées à ton niveau !

✨ FONCTIONNALITÉS

🎤 ENREGISTREMENT FACILE
• 8 secondes suffisent
• Micro de ton téléphone
• Interface simple type Shazam

🎹 4 NIVEAUX AUTOMATIQUES
• Niveau 1 - Hyper Facile : Mélodie simple pour débutants
• Niveau 2 - Facile : Avec accompagnement basse
• Niveau 3 - Moyen : Accords et harmonisation complète
• Niveau 4 - Pro : Arrangement professionnel avec arpèges

📺 PREVIEWS GRATUITS
• 16 secondes par niveau
• Qualité HD 1280×360
• Illimités et gratuits !

💰 DÉBLOCAGE UNIQUE 1$
• Accès complet aux 4 niveaux
• Téléchargement illimité
• Mises à jour gratuites à vie
• Un seul paiement, pour toujours

🎵 MODE PRATIQUE
• Détection intelligente de tes notes
• Feedback visuel immédiat (vert/orange/rouge)
• Score et précision en temps réel
• Progresse à ton rythme

🎨 INTERFACE MODERNE
• Design élégant dark theme
• Animations fluides
• Navigation intuitive

🧠 INTELLIGENCE ARTIFICIELLE
• Extraction automatique des notes (BasicPitch par Spotify)
• Détection tonalité et tempo
• Arrangements musicaux intelligents
• Génération vidéo optimisée

PARFAIT POUR :
• Débutants voulant apprendre le piano
• Pianistes cherchant de nouvelles idées
• Professeurs créant du contenu pédagogique
• Musiciens voulant visualiser leurs morceaux

COMMENT ÇA MARCHE :
1. Appuie sur le bouton et enregistre ~8 secondes
2. L'IA analyse et extrait la mélodie
3. Reçois instantanément 4 versions de difficulté
4. Apprends avec les vidéos animées !

Télécharge maintenant et transforme ton piano ! 🎹✨

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SUPPORT : support@shazapiano.com
FEEDBACK : feedback@shazapiano.com
CONFIDENTIALITÉ : Tes enregistrements sont supprimés après 24h

ShazaPiano © 2025 - Ton piano, 4 niveaux, 1 minute ! 🎹
```

#### Icône de l'application
```
Format : 512×512 PNG
Requis : Oui
Action : Upload icône (À CRÉER - tu peux utiliser Canva ou Figma)
```

#### Graphique de présentation
```
Format : 1024×500 PNG
Requis : Oui
Action : Upload banner (À CRÉER - logo + slogan)
```

### Étape 2.2 : Captures d'écran

**IMPORTANT** : Minimum 2, Maximum 8

**Android Phone - Portrait** (obligatoire) :
```
Taille : Entre 320px et 3840px
Ratio : 16:9 ou 9:16
Nombre : Minimum 2 (recommandé 8)
```

**Screenshots à prendre** (dans l'ordre) :
1. **Home screen** - Bouton central + pastilles L1-L4
2. **Grille vidéos** - 4 tuiles avec previews
3. **Video player** - Lecteur avec controls
4. **Practice mode** - Clavier virtuel + feedback
5. **Paywall** - Modal "Débloquer 1$"
6. **Success state** - Vidéos débloquées
7. **Settings** (si fait)
8. **About** (si fait)

**Action** :
```bash
# Lancer l'app Flutter
cd app
flutter run

# Prendre screenshots (ou utiliser Android Studio)
# Enregistrer dans app/screenshots/
```

---

## 💰 PARTIE 3 : CRÉER LE PRODUIT IAP (CRITIQUE !)

### Étape 3.1 : Accéder aux Produits

**Navigation** : 
```
Monétisation > Produits intégrés à l'application
```

### Étape 3.2 : Créer un Produit Géré

1. **Cliquer** : "Créer un produit géré"

### Étape 3.3 : Informations du Produit

**ID du produit** (CRITIQUE - NE PAS SE TROMPER) :
```
piano_all_levels_1usd
```
⚠️ **ATTENTION** : Cet ID doit être EXACTEMENT celui-ci car il est hardcodé dans `app_constants.dart`

**Nom** :
```
Débloquer tous les niveaux
```

**Description** :
```
Accès complet aux 4 niveaux de difficulté de ShazaPiano. 
Débloquez la lecture complète, le téléchargement illimité 
et toutes les fonctionnalités pour seulement 1$.

Inclus :
• 4 niveaux de difficulté (Facile → Pro)
• Lecture complète des vidéos
• Téléchargement illimité
• Mises à jour gratuites à vie
• Mode pratique complet

Achat unique, accès permanent !
```

### Étape 3.4 : Définir le Prix

**Prix par défaut** :
```
USD : 1.00
EUR : 0.99
(Google calcule automatiquement pour autres devises)
```

**Ou prix local** :
```
☑️ Cocher "Définir des prix locaux"
```

**Disponibilité** :
```
☑️ Disponible
```

### Étape 3.5 : Sauvegarder

1. **Cliquer** : "Enregistrer"
2. **Activer le produit** : Bouton "Activer"

**État final** : "Actif" ✅

---

## 🧪 PARTIE 4 : CONFIGURER LES TESTS

### Étape 4.1 : Testeurs de Licence

**Navigation** : Configuration > Test de licence

**Ajouter testeurs** :
```
1. Cliquer : "Ajouter des testeurs de licence"
2. Entrer emails Gmail (séparés par virgules) :
   - ton.email@gmail.com
   - ami1@gmail.com
   - ami2@gmail.com

3. Enregistrer
```

**Avantage** : Ces comptes peuvent acheter GRATUITEMENT en sandbox !

### Étape 4.2 : Test Interne

**Navigation** : Tests > Test interne

1. **Créer une version de test interne**
2. **Nom de la version** : "Alpha v0.1.0"
3. **Testeurs** : Créer liste emails
4. **Ajouter des testeurs** : 
   ```
   Même emails que ci-dessus
   ```

---

## 📦 PARTIE 5 : PRÉPARER LA VERSION (Build)

### Étape 5.1 : Générer Keystore de Signature

**Sur ton PC** :

```bash
# Aller dans dossier Android
    cd app/android

# Générer keystore
keytool -genkey -v -keystore shazapiano-release.keystore ^
  -alias shazapiano ^
  -keyalg RSA ^
  -keysize 2048 ^
  -validity 10000

# Répondre aux questions :
Mot de passe du fichier de clés : [CHOISIS UN MOT DE PASSE FORT - NOTE-LE !]
Ressaisir le nouveau mot de passe : [MÊME MOT DE PASSE]
Prénom et nom : Ludo
Nom de votre unité organisationnelle : ShazaPiano
Nom de votre organisation : ShazaPiano
Ville ou localité : Paris
État ou province : Île-de-France
Code pays à deux lettres : FR

Confirmer ? [oui] : oui

Mot de passe de la clé : [MÊME MOT DE PASSE ou ENTER pour identique]
```

**IMPORTANT** : 🔑 **SAUVEGARDER LE MOT DE PASSE** dans un endroit sûr !

### Étape 5.2 : Créer key.properties

```bash
# Dans app/android/
    cd app/android

# Créer fichier key.properties (PowerShell)
@"
storePassword=TON_MOT_DE_PASSE_ICI
keyPassword=TON_MOT_DE_PASSE_ICI
keyAlias=shazapiano
storeFile=../shazapiano-release.keystore
"@ | Out-File -FilePath app\key.properties -Encoding UTF8
```

**Remplace** `TON_MOT_DE_PASSE_ICI` par ton mot de passe réel !

⚠️ **NE JAMAIS COMMIT** key.properties (déjà dans .gitignore ✅)

### Étape 5.3 : Build App Bundle

```bash
# Retour au dossier app
    cd app

# Installer dépendances
flutter pub get

# Générer code (.g.dart files)
flutter pub run build_runner build --delete-conflicting-outputs

# Build AAB signé
flutter build appbundle --release

# Fichier créé dans :
# build\app\outputs\bundle\release\app-release.aab
```

**Vérification** :
```bash
# Vérifier que le fichier existe
dir build\app\outputs\bundle\release\app-release.aab

# Taille attendue : ~30-50 MB
```

---

## 📤 PARTIE 6 : UPLOAD SUR PLAY CONSOLE

### Étape 6.1 : Créer une Version de Test

**Navigation** : Tests > Test interne > Créer une version

### Étape 6.2 : Upload AAB

1. **Dans la section "App bundles"**
2. **Cliquer** : "Importer"
3. **Sélectionner** : `app-release.aab`
4. **Attendre** : Upload (peut prendre 2-5 minutes)

**Google va automatiquement** :
- ✅ Analyser l'AAB
- ✅ Vérifier signature
- ✅ Générer APKs pour chaque device
- ✅ Optimiser la taille

### Étape 6.3 : Notes de Version

**Ajouter notes pour testeurs** :
```
🎹 ShazaPiano Alpha v0.1.0

Première version de test !

À tester :
✅ Enregistrement audio (bouton central)
✅ Génération des 4 vidéos
✅ Previews 16 secondes
✅ Achat 1$ (GRATUIT pour vous en test)
✅ Restaurer l'achat
✅ Mode pratique

Feedback bienvenu : feedback@shazapiano.com

Merci de tester ! 🙏
```

### Étape 6.4 : Vérifier et Publier

1. **Vérifier** : Pas d'erreurs rouges
2. **Cliquer** : "Enregistrer"
3. **Cliquer** : "Vérifier la version"
4. **Corriger** erreurs/avertissements si nécessaire
5. **Cliquer** : "Déployer la version en test interne"

**Status** : "En attente d'examen" (max 2h généralement)

---

## 📝 PARTIE 7 : COMPLÉTER LA FICHE (OBLIGATOIRE)

### Étape 7.1 : Présence sur Google Play

**Sections OBLIGATOIRES à compléter** :

#### A) Fiche du Play Store
- ✅ Déjà fait dans Partie 2

#### B) Catégorie de l'application
```
Catégorie : Éducation
Tags : Piano, Musique, Apprentissage, Éducation musicale
```

#### C) Coordonnées
```
Site web : https://github.com/sky1241/shazam-piano (temporaire)
Email : ludo@shazapiano.com
Téléphone : (optionnel)

Adresse (requise pour apps avec IAP) :
[Ton adresse]
[Code postal] [Ville]
France
```

---

### Étape 7.2 : Politique de Confidentialité (OBLIGATOIRE)

**Tu as 2 options** :

#### Option A : Héberger sur GitHub Pages (RAPIDE)
```bash
# 1. Créer repo public : shazapiano-privacy
# 2. Activer GitHub Pages
# 3. Upload PRIVACY_POLICY.md comme index.html
```

#### Option B : Utiliser un service gratuit

**Termly** (gratuit) :
```
1. Aller sur : https://termly.io/
2. Générer Privacy Policy gratuite
3. Copier l'URL
```

**URL à mettre dans Play Console** :
```
https://TON_URL_ICI.com/privacy-policy
```

---

### Étape 7.3 : Classification du Contenu

**Navigation** : Contenu de l'application > Classification du contenu

**Questionnaire** (Répondre honnêtement) :

```
Adresse e-mail : ludo@shazapiano.com

Violence :
Q: Contenu violent ? 
R: ☐ Non

Contenu sexuel :
Q: Contenu sexuel ?
R: ☐ Non

Blasphème :
Q: Blasphème ?
R: ☐ Non

Drogues :
Q: Référence drogues/alcool ?
R: ☐ Non

Thèmes sensibles :
Q: Thèmes sensibles ?
R: ☐ Non

```

**Résultat attendu** : Classement PEGI 3 / Everyone

**Enregistrer** → **Soumettre**

---

### Étape 7.4 : Public Cible

**Navigation** : Contenu de l'application > Public cible et contenu

**Tranche d'âge cible** :
```
☑️ 13 ans et plus
☐ Moins de 13 ans (éviter - nécessite COPPA compliance)
```

**Cliquer** : Enregistrer

---

### Étape 7.5 : Actualités

**Navigation** : Contenu de l'application > Actualités

```
Cette application constitue-t-elle une actualité ?
☐ Non
```

**Enregistrer**

---

### Étape 7.6 : Déclaration COVID-19

```
Cette application suit-elle les directives COVID-19 ?
☑️ Non applicable (app musicale)
```

---

## 🎯 PARTIE 8 : CONFIGURER LES PARAMÈTRES

### Étape 8.1 : Disponibilité

**Navigation** : Version > Production > Pays et régions

**Pays disponibles** :
```
☑️ Tous les pays (recommandé)

Ou sélectionner :
☑️ France
☑️ Belgique
☑️ Suisse
☑️ Canada
☑️ États-Unis
☑️ Royaume-Uni
... (ajouter plus si voulu)
```

### Étape 8.2 : Pricing (Déjà fait)

```
Application gratuite ✅
IAP : 1$ (déjà configuré en Partie 3)
```

---

## 🧪 PARTIE 9 : TESTER L'IAP

### Étape 9.1 : Installer Version Test

1. **Les testeurs reçoivent** email avec lien
2. **Ou aller** : Play Console > Test interne > URL de test
3. **Copier lien** et envoyer aux testeurs
4. **Installer** app depuis le lien

### Étape 9.2 : Tester l'Achat

**En tant que testeur** :

1. **Lancer** ShazaPiano
2. **Enregistrer** 8s de piano (ou simuler)
3. **Voir** les 4 previews 16s
4. **Cliquer** "Débloquer pour 1$"
5. **Dialog Google Play** s'affiche avec **"Test"** marqué
6. **Acheter** (GRATUIT pour testeurs !)
7. **Vérifier** : Vidéos débloquées ✅

### Étape 9.3 : Tester Restore

1. **Désinstaller** app
2. **Réinstaller**
3. **Cliquer** "Restaurer l'achat"
4. **Vérifier** : Déjà débloqué ✅

---

## 🚀 PARTIE 10 : PASSER EN PRODUCTION

### Étape 10.1 : Compléter les Sections Manquantes

**Play Console Dashboard** montre toutes sections :

Vérifier que **TOUT est vert** ✅ :
- ✅ Fiche du Play Store
- ✅ Classification du contenu
- ✅ Public cible
- ✅ Politique de confidentialité
- ✅ Captures d'écran (min 2)
- ✅ Icône application
- ✅ Graphique présentation

### Étape 10.2 : Créer Version Production

**Navigation** : Version > Production > Créer une version

1. **Upload** même `app-release.aab`
2. **Notes de version** (visible par users) :

```
Version 1.0.0 - Lancement initial ! 🎹

🆕 Nouveautés :
• Enregistrement piano en 8 secondes
• Génération automatique 4 niveaux de difficulté
• Previews gratuits 16 secondes par niveau
• Mode pratique avec détection des notes
• Interface moderne et intuitive

💰 Monétisation :
• Application gratuite
• Déblocage optionnel 1$ pour accès complet

Merci d'utiliser ShazaPiano !
Feedback : feedback@shazapiano.com
```

### Étape 10.3 : Déploiement Progressif

**Options de déploiement** :

```
☑️ Déploiement progressif
  10% pendant 2 jours
  50% pendant 3 jours
  100% après validation

Ou :

☑️ Déploiement complet immédiat (si confiant)
```

**Recommandation** : Progressif pour monitorer bugs

### Étape 10.4 : Soumettre pour Examen

1. **Cliquer** : "Vérifier la version"
2. **Corriger** erreurs s'il y en a
3. **Cliquer** : "Déployer en production"

**Délai examen Google** : 1-7 jours (souvent 24-48h)

---

## 📧 PARTIE 11 : APRÈS SOUMISSION

### Ce qui se passe

1. **Soumission** : Status "En attente d'examen"
2. **Examen automatique** : Scan sécurité (quelques heures)
3. **Examen manuel** : Team Google (1-7 jours)
4. **Notification** : Email de Google

### États possibles

**✅ Approuvé** :
```
Status : "Publication en cours"
Délai : 1-24h pour être visible
Action : Partager lien Play Store !
```

**⚠️ Modifications requises** :
```
Status : "Modifications requises"
Email : Détails des problèmes
Action : Corriger et re-soumettre
```

**❌ Rejeté** :
```
Status : "Rejeté"
Raison : Violation règles (rare si tu suis ce guide)
Action : Lire raison, corriger, re-soumettre
```

---

## 🔗 PARTIE 12 : LIEN PLAY STORE

### Une fois approuvé

**Ton lien Play Store sera** :
```
https://play.google.com/store/apps/details?id=com.ludo.shazapiano
```

**Partager** :
- Sur réseaux sociaux
- Dans ta bio
- À tes amis
- Sur forums piano

---

## 📊 PARTIE 13 : MONITORING POST-LANCEMENT

### Dashboard à surveiller

**Navigation** : Statistiques > Tableau de bord

**Métriques clés** :
- Installations
- Désinstallations
- Crashes (objectif : <1%)
- ANR (objectif : <0.5%)
- Évaluations (objectif : >4.0⭐)
- Revenus IAP

### Répondre aux avis

**IMPORTANT** : Répondre rapidement aux avis

**Template réponse positive** :
```
Merci beaucoup pour les 5 étoiles ! 🎹
Content que ShazaPiano t'aide à progresser au piano !
N'hésite pas à partager l'app si elle te plaît.
- L'équipe ShazaPiano
```

**Template réponse négative** :
```
Désolé pour les problèmes rencontrés ! 😔
Peux-tu m'envoyer plus de détails à support@shazapiano.com ?
Je vais corriger ça rapidement.
Merci de ta patience !
- Ludo, ShazaPiano
```

---

## ✅ CHECKLIST FINALE GOOGLE PLAY

### Avant Soumission
- [ ] App créée dans console ✅
- [ ] Produit IAP créé avec ID exact : `piano_all_levels_1usd` ✅
- [ ] Prix 1$ configuré ✅
- [ ] Testeurs de licence ajoutés
- [ ] Keystore généré et sauvegardé 🔑
- [ ] key.properties créé (NON commité)
- [ ] AAB signé buildé
- [ ] Fiche Play Store complétée
- [ ] Screenshots uploadés (min 2)
- [ ] Icône 512×512 uploadée
- [ ] Graphique 1024×500 uploadé
- [ ] Description écrite
- [ ] Classification contenu faite (PEGI 3)
- [ ] Public cible défini (13+)
- [ ] Politique confidentialité URL ajoutée
- [ ] Email contact ajouté
- [ ] Pays disponibilité sélectionnés

### Après Soumission
- [ ] Version soumise en test interne
- [ ] Testeurs invités (5-10 personnes)
- [ ] Tests effectués (IAP, features, bugs)
- [ ] Bugs critiques fixés
- [ ] Version soumise en production
- [ ] Approbation Google reçue
- [ ] App visible sur Play Store 🎉

---

## 🎯 TIMELINE ESTIMÉE

```
Jour 1 (Aujourd'hui) - 2h :
├─ Créer app Play Console (15 min)
├─ Créer produit IAP (15 min)
├─ Compléter fiche store (45 min)
├─ Générer keystore (15 min)
└─ Build AAB (30 min)

Jour 2 - 1h :
├─ Screenshots (30 min)
├─ Upload version test (15 min)
└─ Inviter testeurs (15 min)

Jours 3-7 - Tests :
├─ Testeurs installent
├─ Tests fonctionnels
├─ Rapports bugs
└─ Corrections

Jour 8 - Production :
├─ Upload version production
└─ Attente examen Google (1-7 jours)

Jour 15 - LIVE ! 🎉
└─ App disponible publiquement
```

---

## 💡 CONSEILS PRO

### 1. Screenshots de Qualité
```
- Utilise des vrais enregistrements
- Montre le flow complet
- Highlight les features clés
- Clean UI sans debug info
- Bon lighting
```

### 2. Description Optimisée SEO
```
Mots-clés importants (déjà dans description) :
- Piano
- Apprendre
- Vidéos
- Pédagogique
- Intelligence artificielle
- Gratuit
- Musique
```

### 3. Prix IAP Optimal
```
1.00 USD = Prix psychologique parfait
- Pas trop cher (barrière basse)
- Pas trop cheap (perçu comme qualité)
- Conversion optimale
```

### 4. Réponses Rapides
```
- Répondre aux avis <24h
- Montrer que tu écoutes
- Fix bugs rapidement
- Update régulièrement
```

---

## 🚨 ERREURS À ÉVITER

### ❌ NE PAS :
- Oublier de signer l'AAB
- Utiliser mauvais ID produit IAP
- Oublier politique confidentialité
- Soumettre sans tester
- Ignorer les avertissements Google
- Mettre email personnel (utiliser domaine)

### ✅ TOUJOURS :
- Tester IAP en sandbox d'abord
- Avoir plusieurs testeurs
- Sauvegarder keystore en lieu sûr
- Lire feedback Google attentivement
- Monitorer crashes

---

## 📞 AIDE

### Problèmes Play Console ?

**Documentation Google** :
https://support.google.com/googleplay/android-developer

**Email Google** :
Via Play Console > Help > Contact us

**Support ShazaPiano** :
ludo@shazapiano.com

---

## 🎉 FÉLICITATIONS !

Une fois ces étapes complétées, **ShazaPiano sera sur le Play Store** ! 🎹

**Next** : Marketing, user acquisition, updates, features !

---

## 📋 RÉCAP ULTRA-RAPIDE

```bash
# 1. Créer app Play Console
Nom : ShazaPiano
Type : Gratuite
Catégorie : Éducation

# 2. Créer produit IAP
ID : piano_all_levels_1usd
Prix : 1.00 USD
Type : Non-consommable

# 3. Build AAB
cd app
keytool -genkey ... (générer keystore)
flutter build appbundle --release

# 4. Upload
Play Console > Test interne > Upload AAB

# 5. Compléter fiche
Screenshots + Description + Privacy Policy

# 6. Tester
Inviter testeurs > Tester IAP > Fix bugs

# 7. Production
Upload production > Examen Google > LIVE ! 🎉
```

---

**🎹 Tu es maintenant prêt pour le Play Store ! 🚀**

**Questions ?** ludo@shazapiano.com
