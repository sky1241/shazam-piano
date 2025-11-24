# Contributing to ShazaPiano

Merci de vouloir contribuer à ShazaPiano ! 🎹

## 📋 Table des Matières

- [Code de Conduite](#code-de-conduite)
- [Comment Contribuer](#comment-contribuer)
- [Setup Développement](#setup-développement)
- [Standards de Code](#standards-de-code)
- [Tests](#tests)
- [Pull Requests](#pull-requests)

---

## Code de Conduite

Ce projet suit un code de conduite simple :
- Soyez respectueux
- Soyez constructif
- Soyez professionnel

---

## Comment Contribuer

### 🐛 Rapporter un Bug

1. Vérifiez que le bug n'a pas déjà été signalé dans les [Issues](https://github.com/sky1241/shazam-piano/issues)
2. Ouvrez une nouvelle issue avec :
   - Titre clair et descriptif
   - Steps pour reproduire
   - Comportement attendu vs actuel
   - Screenshots si applicable
   - Version Flutter/Python
   - OS et device

### 💡 Suggérer une Fonctionnalité

1. Vérifiez que la fonctionnalité n'existe pas déjà
2. Ouvrez une issue avec le tag `enhancement`
3. Décrivez clairement :
   - Le problème résolu
   - La solution proposée
   - Des alternatives considérées

### 🔧 Contribuer du Code

1. Fork le projet
2. Créez une branche (`git checkout -b feature/AmazingFeature`)
3. Committez vos changements (`git commit -m 'Add AmazingFeature'`)
4. Push vers la branche (`git push origin feature/AmazingFeature`)
5. Ouvrez une Pull Request

---

## Setup Développement

### Prérequis

- Python 3.10+
- Flutter 3.16+
- FFmpeg
- Git

### Installation

```bash
# Clone le repo
git clone https://github.com/sky1241/shazam-piano.git
cd shazam-piano

# Run setup script
chmod +x scripts/setup.sh
./scripts/setup.sh
```

### Backend

```bash
cd backend
source .venv/bin/activate  # Windows: .venv\Scripts\activate
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

### Flutter

```bash
cd app
flutter pub get
flutter run
```

---

## Standards de Code

### Python (Backend)

**Style**: PEP 8

```bash
# Format code
black .

# Lint
flake8 . --max-line-length=100

# Type checking
mypy .
```

**Guidelines**:
- Docstrings pour toutes les fonctions publiques
- Type hints partout
- Noms de variables descriptifs
- Max 100 caractères par ligne
- Comments en français acceptable

### Dart (Flutter)

**Style**: Dart official style guide

```bash
# Format code
dart format .

# Analyze
flutter analyze

# Fix
dart fix --apply
```

**Guidelines**:
- Use `const` quand possible
- Prefer `final` over `var`
- Document public APIs
- Follow Material Design 3
- Widgets composables et réutilisables

### Commits

Format: [Conventional Commits](https://www.conventionalcommits.org/)

```
type(scope): subject

body (optionnel)

footer (optionnel)
```

**Types**:
- `feat`: Nouvelle fonctionnalité
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting, pas de code change
- `refactor`: Refactoring
- `test`: Ajout tests
- `chore`: Maintenance

**Exemples**:
```
feat(backend): add audio synthesis with FluidSynth
fix(flutter): resolve IAP purchase flow issue
docs: update Firebase setup guide
```

---

## Tests

### Backend

```bash
cd backend
pytest --cov=. --cov-report=html
```

**Couverture minimale**: 70%

### Flutter

```bash
cd app
flutter test --coverage
```

**Guidelines**:
- Test unitaires pour business logic
- Widget tests pour UI
- Integration tests pour flows critiques
- Mock external dependencies

---

## Pull Requests

### Checklist

Avant de soumettre une PR, vérifiez :

- [ ] Code compilé sans erreur
- [ ] Tests passent (backend + flutter)
- [ ] Linting passé (black, flutter analyze)
- [ ] Documentation mise à jour si besoin
- [ ] CHANGELOG.md mis à jour
- [ ] Commit messages suivent convention
- [ ] PR title est descriptif
- [ ] Description explique les changements
- [ ] Screenshots si changement UI

### Review Process

1. **Automated checks** doivent passer (CI/CD)
2. **Code review** par au moins 1 maintainer
3. **Testing** sur device réel si UI changes
4. **Merge** par maintainer après approval

### Guidelines

- Keep PRs focused (une feature/fix à la fois)
- Petits PRs preferred (< 500 lignes)
- Rebasing plutôt que merge commits
- Répondre rapidement aux review comments

---

## Structure Projet

```
shazapiano/
├── backend/          # FastAPI backend
│   ├── app.py
│   ├── inference.py
│   ├── arranger.py
│   ├── render.py
│   └── tests/
│
├── app/             # Flutter app
│   └── lib/
│       ├── core/
│       ├── data/
│       ├── domain/
│       └── presentation/
│
├── docs/            # Documentation
├── infra/           # Docker, CI/CD
└── scripts/         # Utility scripts
```

---

## Questions ?

- 📖 Lis d'abord la [Documentation](docs/)
- 💬 Ouvre une [Discussion](https://github.com/sky1241/shazam-piano/discussions)
- 🐛 Crée une [Issue](https://github.com/sky1241/shazam-piano/issues)

---

## Licence

En contribuant, vous acceptez que vos contributions soient sous la même [licence](LICENSE) que le projet.

---

**Merci de contribuer à ShazaPiano ! 🎹**

