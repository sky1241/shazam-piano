# ShazaPiano - API Reference

Documentation complète de l'API Backend.

**Base URL (Dev)** : `http://localhost:8000`  
**Base URL (Prod)** : `https://shazapiano-backend.fly.dev`

---

## 📡 Endpoints

### GET `/`

Root endpoint - Informations basiques.

**Response** :
```json
{
  "status": "ok",
  "timestamp": "2025-11-24T03:00:00",
  "version": "1.0.0"
}
```

---

### GET `/health`

Health check endpoint - Pour monitoring.

**Response** :
```json
{
  "status": "healthy",
  "timestamp": "2025-11-24T03:00:00",
  "version": "1.0.0"
}
```

**Status Codes** :
- `200` : Service is healthy
- `500` : Service has issues

---

### POST `/process`

Upload audio et génère 4 vidéos piano.

**Request** :

```bash
curl -X POST http://localhost:8000/process \
  -F "audio=@recording.m4a" \
  -F "with_audio=false" \
  -F "levels=1,2,3,4"
```

**Parameters** :

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `audio` | File | ✅ Yes | Audio file (m4a, wav, mp3) - Max 10MB |
| `with_audio` | Boolean | No | Include synthesized audio (default: false) |
| `levels` | String | No | Comma-separated levels (default: "1,2,3,4") |

**Response** :

```json
{
  "job_id": "20251124_030700_12345",
  "timestamp": "2025-11-24T03:07:00",
  "levels": [
    {
      "level": 1,
      "name": "Hyper Facile",
      "preview_url": "/media/out/jobid_L1_preview.mp4",
      "video_url": "/media/out/jobid_L1_full.mp4",
      "midi_url": "/media/out/jobid_L1.mid",
      "key_guess": "C",
      "tempo_guess": 120,
      "duration_sec": 8.5,
      "status": "success",
      "error": null
    },
    {
      "level": 2,
      "name": "Facile",
      "preview_url": "/media/out/jobid_L2_preview.mp4",
      "video_url": "/media/out/jobid_L2_full.mp4",
      "midi_url": "/media/out/jobid_L2.mid",
      "key_guess": "C",
      "tempo_guess": 120,
      "duration_sec": 9.4,
      "status": "success",
      "error": null
    },
    // ... L3, L4
  ]
}
```

**Status Codes** :
- `200` : Success
- `400` : Invalid parameters
- `413` : File too large
- `422` : Validation error
- `500` : Processing error

**Error Response** :
```json
{
  "detail": "Aucune mélodie détectable. Essayez un environnement plus silencieux."
}
```

---

### GET `/media/out/{filename}`

Télécharge une vidéo ou fichier MIDI généré.

**Request** :
```bash
GET /media/out/20251124_030700_12345_L1_full.mp4
```

**Response** : Binary file (MP4 or MIDI)

**Headers** :
- `Content-Type: video/mp4` or `audio/midi`
- `Content-Disposition: inline` or `attachment`

---

### DELETE `/cleanup/{job_id}`

Supprime tous les fichiers associés à un job.

**Request** :
```bash
DELETE /cleanup/20251124_030700_12345
```

**Response** :
```json
{
  "status": "ok",
  "deleted": [
    "20251124_030700_12345_input.m4a",
    "20251124_030700_12345_L1_full.mp4",
    "20251124_030700_12345_L1_preview.mp4",
    "20251124_030700_12345_L1.mid",
    // ... other files
  ]
}
```

---

## 📊 Models

### LevelResult

```typescript
{
  level: number;           // 1-4
  name: string;            // "Hyper Facile", "Facile", "Moyen", "Pro"
  preview_url: string;     // URL preview 16s
  video_url: string;       // URL vidéo complète
  midi_url: string;        // URL fichier MIDI
  key_guess: string;       // "C", "Am", "G", etc.
  tempo_guess: number;     // BPM
  duration_sec: number;    // Durée en secondes
  status: string;          // "success", "error", "pending"
  error: string | null;    // Message d'erreur si échec
}
```

### ProcessResponse

```typescript
{
  job_id: string;          // Unique job identifier
  timestamp: string;       // ISO 8601 timestamp
  levels: LevelResult[];   // Array of 4 level results
}
```

---

## 🚨 Error Codes

| Code | Message | Description |
|------|---------|-------------|
| `no_audio` | Aucun audio détecté | Fichier audio vide ou corrompu |
| `no_melody` | Aucune mélodie détectable | Signal trop bruité ou pas de notes |
| `too_long` | Audio trop long | Dépasse 15 secondes |
| `too_large` | Fichier trop volumineux | Dépasse 10 MB |
| `processing_failed` | Erreur de génération | Erreur interne serveur |
| `invalid_level` | Niveau invalide | Level doit être 1, 2, 3, ou 4 |

---

## ⏱️ Timeouts

| Operation | Timeout |
|-----------|---------|
| FFmpeg conversion | 15s |
| BasicPitch extraction | 10s |
| Video rendering | 20s per level |
| Total request | 5 minutes |

---

## 📏 Limits

| Resource | Limit |
|----------|-------|
| Max upload size | 10 MB |
| Max audio duration | 15 seconds |
| Max concurrent requests | 20 per minute per IP |
| Retention - Input files | 24 hours |
| Retention - Output files | 7 days |

---

## 🔐 Authentication

Currently : **No authentication required**

Future versions may include:
- Firebase token validation
- API key per user
- Rate limiting per user (not just IP)

---

## 📝 Examples

### Python

```python
import requests

# Upload audio
with open('recording.m4a', 'rb') as f:
    files = {'audio': f}
    data = {'with_audio': 'false', 'levels': '1,2,3,4'}
    
    response = requests.post(
        'http://localhost:8000/process',
        files=files,
        data=data
    )
    
    result = response.json()
    print(f"Job ID: {result['job_id']}")
    
    for level in result['levels']:
        print(f"Level {level['level']}: {level['name']}")
        print(f"  Video: {level['video_url']}")
```

### JavaScript

```javascript
const formData = new FormData();
formData.append('audio', audioFile);
formData.append('with_audio', 'false');
formData.append('levels', '1,2,3,4');

const response = await fetch('http://localhost:8000/process', {
  method: 'POST',
  body: formData
});

const result = await response.json();
console.log('Job ID:', result.job_id);

result.levels.forEach(level => {
  console.log(`Level ${level.level}: ${level.name}`);
  console.log(`Video: ${level.video_url}`);
});
```

### Dart (Flutter)

```dart
final dio = Dio();
final formData = FormData.fromMap({
  'audio': await MultipartFile.fromFile(audioPath),
  'with_audio': false,
  'levels': '1,2,3,4',
});

final response = await dio.post(
  'http://10.0.2.2:8000/process',
  data: formData,
);

final result = ProcessResponseDto.fromJson(response.data);
print('Job ID: ${result.jobId}');

for (final level in result.levels) {
  print('Level ${level.level}: ${level.name}');
  print('Video: ${level.videoUrl}');
}
```

---

## 🔄 Webhooks (Future)

Planned for future versions:

```bash
POST /process?webhook_url=https://your-app.com/callback

# Server will POST to callback URL when processing complete
```

---

## 📊 Rate Limiting

Current: **20 requests per minute per IP**

Headers returned:
```
X-RateLimit-Limit: 20
X-RateLimit-Remaining: 15
X-RateLimit-Reset: 1732420800
```

When exceeded:
```json
{
  "detail": "Rate limit exceeded. Try again in 60 seconds."
}
```

---

## 🌐 CORS

Currently: **All origins allowed** (`*`)

Production should restrict to:
```python
allow_origins=["https://shazapiano.com", "app://shazapiano"]
```

---

## 📚 OpenAPI / Swagger

Interactive API documentation:

**Development** : http://localhost:8000/docs  
**Production** : https://shazapiano-backend.fly.dev/docs

Alternative (ReDoc): `/redoc`

---

## 🧪 Testing API

### Using curl

```bash
# Health check
curl http://localhost:8000/health

# Process audio
curl -X POST http://localhost:8000/process \
  -F "audio=@test.m4a" \
  -F "levels=1"

# Cleanup
curl -X DELETE http://localhost:8000/cleanup/test_job_123
```

### Using httpie

```bash
# Install: pip install httpie

# Process
http POST localhost:8000/process \
  audio@recording.m4a \
  with_audio=false \
  levels="1,2,3,4"
```

### Using Postman

1. Import OpenAPI spec from `/openapi.json`
2. Set base URL
3. Test endpoints with UI

---

## 🔗 Related Documentation

- [Architecture](ARCHITECTURE.md)
- [Deployment](DEPLOYMENT.md)
- [Firebase Setup](SETUP_FIREBASE.md)

---

**API Version** : 1.0.0  
**Last Updated** : November 24, 2025

