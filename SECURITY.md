# Security Policy

## Supported Versions

Currently supported versions of ShazaPiano:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x:                |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please follow these steps:

### 1. **DO NOT** Create a Public Issue

Please do not open a public GitHub issue for security vulnerabilities.

### 2. Report Privately

Send details to: **security@shazapiano.com** (or ludo@shazapiano.com)

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### 3. Response Timeline

- **24 hours**: Initial response confirming receipt
- **72 hours**: Assessment of severity
- **7 days**: Plan for fix (if confirmed)
- **30 days**: Security patch release

### 4. Disclosure Policy

- We request 90 days before public disclosure
- We will credit you in security advisories (unless you prefer anonymity)
- Responsible disclosure is appreciated

## Security Best Practices

### For Developers

**Backend**:
- Always validate user input
- Use parameterized queries
- Keep dependencies updated
- Never commit secrets (.env files)
- Use HTTPS in production
- Implement rate limiting

**Flutter**:
- Validate API responses
- Secure local storage (encryption)
- Use HTTPS for all requests
- Obfuscate sensitive data
- Implement certificate pinning
- Validate IAP receipts server-side

### For Users

- Keep app updated
- Use strong passwords (if auth is added)
- Don't share IAP receipts
- Report suspicious behavior

## Known Security Considerations

### Current Implementation

1. **Firebase Rules**: Ensure Firestore rules are properly configured before production
2. **IAP Validation**: Consider server-side receipt validation for production
3. **API Keys**: Firebase API keys are public by design (secured by rules)
4. **Backend API**: Add authentication for production deployment

### Planned Improvements

- [ ] Server-side IAP receipt validation
- [ ] Rate limiting per user (not just IP)
- [ ] Request signing for API calls
- [ ] Certificate pinning in Flutter
- [ ] Encrypted local storage for sensitive data

## Dependencies

We monitor dependencies for known vulnerabilities:

- **Backend**: Using Dependabot for Python packages
- **Flutter**: Regular `flutter pub outdated` checks
- **Docker**: Base images from official sources only

### Updating Dependencies

```bash
# Backend
cd backend
pip install --upgrade pip
pip list --outdated

# Flutter
cd app
flutter pub outdated
flutter pub upgrade
```

## Secure Development

### Code Review

All code changes require:
- Peer review
- Security considerations check
- Test coverage
- CI/CD passing

### Secrets Management

**NEVER commit**:
- `.env` files
- API keys
- Private keys
- `google-services.json`
- Firebase config with secrets

**Use**:
- Environment variables
- GitHub Secrets (for CI/CD)
- Firebase Remote Config (for app configs)

### Testing

Security testing includes:
- Input validation tests
- Authentication tests
- Authorization tests
- Rate limiting tests
- SQL/NoSQL injection tests

## Incident Response

In case of a security incident:

1. **Immediate**: Take affected systems offline
2. **Assess**: Determine scope and impact
3. **Notify**: Inform affected users within 72 hours
4. **Fix**: Deploy security patch
5. **Review**: Post-mortem and prevention measures

## Security Checklist for Production

### Backend
- [ ] HTTPS enforced
- [ ] Rate limiting active
- [ ] CORS properly configured
- [ ] Input validation on all endpoints
- [ ] Secrets in environment variables
- [ ] Logging without sensitive data
- [ ] Error messages don't leak info

### Flutter
- [ ] API calls over HTTPS
- [ ] Certificate pinning enabled
- [ ] Local storage encrypted
- [ ] No hardcoded secrets
- [ ] Obfuscation enabled
- [ ] Debug logs disabled

### Infrastructure
- [ ] Firestore rules tested
- [ ] Firebase Auth configured
- [ ] Cloud Functions secured
- [ ] Monitoring and alerts set up
- [ ] Backup strategy in place

## Contact

For security concerns:
- Email: security@shazapiano.com
- PGP Key: [To be added]

For general inquiries:
- Email: ludo@shazapiano.com
- GitHub: @sky1241

---

**Thank you for helping keep ShazaPiano secure! 🔒**


