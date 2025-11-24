# Scripts Directory

Utility scripts for ShazaPiano development and deployment.

---

## 📜 Available Scripts

### Setup Scripts

#### `setup.sh` (Linux/Mac)
Complete development environment setup.

```bash
chmod +x setup.sh
./setup.sh
```

**Does**:
- Checks Python, Flutter, FFmpeg
- Creates Python virtual environment
- Installs all dependencies (backend + Flutter)
- Runs code generation
- Verifies Firebase config

**Time**: ~10 minutes

#### `setup.ps1` (Windows)
Same as setup.sh but for PowerShell.

```powershell
.\setup.ps1
```

---

### Run Scripts

#### `run-backend.ps1` (Windows)
Quick start for backend server.

```powershell
.\run-backend.ps1
```

Starts Uvicorn on http://localhost:8000

---

### Test Scripts

#### `test.sh` (Linux/Mac)
Runs all tests (backend + Flutter).

```bash
chmod +x test.sh
./test.sh
```

**Runs**:
- Backend pytest with coverage
- Flutter tests with coverage
- Generates HTML coverage reports

**Time**: ~2 minutes

---

### Deployment Scripts

#### `deploy.sh` (Linux/Mac)
Automated deployment to production.

```bash
chmod +x deploy.sh
./deploy.sh [target]
```

**Targets**:
- `fly` - Deploy backend to Fly.io
- `railway` - Deploy backend to Railway
- `docker` - Build and push Docker image
- `flutter` - Build Flutter release AAB
- `all` - Deploy everything

**Features**:
- Pre-deployment tests
- Git status check
- Automated deployment
- Post-deployment verification

---

## 🔧 Usage Examples

### First Time Setup

```bash
# Linux/Mac
./scripts/setup.sh

# Windows
.\scripts\setup.ps1
```

### Daily Development

```bash
# Terminal 1: Backend
make backend-run
# Or: cd backend && source .venv/bin/activate && uvicorn app:app --reload

# Terminal 2: Flutter
make flutter-run
# Or: cd app && flutter run
```

### Before Committing

```bash
# Run tests
./scripts/test.sh

# Or with Make
make test
```

### Deploying to Production

```bash
# Deploy backend
./scripts/deploy.sh fly

# Build Flutter
./scripts/deploy.sh flutter
```

---

## 📝 Adding New Scripts

When adding new scripts:

1. Make them executable:
```bash
chmod +x scripts/your-script.sh
```

2. Add shebang:
```bash
#!/bin/bash
set -e  # Exit on error
```

3. Add to Makefile if useful

4. Document here

5. Test on clean system

---

## 🐛 Troubleshooting Scripts

### Permission denied

```bash
chmod +x scripts/*.sh
```

### Script not found

```bash
# Run from project root
cd "C:\Users\ludov\OneDrive\Bureau\shazam piano"
./scripts/setup.sh
```

### Virtual environment not activated (setup.sh)

```bash
# Manually activate
source backend/.venv/bin/activate  # Linux/Mac
backend\.venv\Scripts\Activate.ps1  # Windows
```

---

## 🔗 Related

- [Makefile](../Makefile) - Alternative command shortcuts
- [QUICK_START.md](../QUICK_START.md) - Quick start guide
- [DEPLOYMENT.md](../docs/DEPLOYMENT.md) - Deployment guide

---

**Happy scripting! 🚀**

