# Security Guidelines for Market Watcher

A practical security checklist for building this real-time market monitoring platform. These are foundational best practices.

---

## 1. API Security (FastAPI Backend)

### Authentication & Authorization
- **Protect endpoints:** Only allow authenticated users to access market data, alerts, and replay features.
  - Use Firebase Auth (already planned) to verify user identity.
  - Check user token on every protected endpoint.
- **Example:**
  ```python
  @app.get("/api/metrics")
  async def get_metrics(current_user: User = Depends(verify_firebase_token)):
      # Only logged-in users can access
      return metrics
  ```

### Input Validation
- **Validate all incoming data:** Query parameters, JSON bodies, headers.
  - Use FastAPI's `Pydantic` models to enforce type and format constraints.
  - Reject malformed requests early.
- **Example:**
  ```python
  class ReplayRequest(BaseModel):
      alert_id: str = Field(..., min_length=1, max_length=50)
      symbol: str = Field(..., regex="^[A-Z0-9]{1,10}$")  # Whitelist format
  ```

### Rate Limiting
- **Prevent abuse:** Limit requests per user/IP to avoid DDoS or resource exhaustion.
  - Use a library like `slowapi` with Redis backend.
  - Example: 100 requests/minute per user, 1000/hour per IP.

### HTTPS Only
- **Always use TLS/SSL** in production (Render.com, Vercel enforce this automatically).
- **Disable insecure protocols:** No plain HTTP in cloud deployment.

### CORS (Cross-Origin Resource Sharing)
- **Restrict origins:** Only allow requests from your frontend domain.
  ```python
  app.add_middleware(
      CORSMiddleware,
      allow_origins=["https://yourfrontend.vercel.app"],  # Whitelist only
      allow_credentials=True,
      allow_methods=["GET", "POST"],
      allow_headers=["*"],
  )
  ```

---

## 2. Database Security (PostgreSQL + TimescaleDB)

### Credentials & Secrets
- **Never hardcode passwords** in source code.
  - Store `DB_USER`, `DB_PASSWORD`, `DB_HOST` in environment variables.
  - Use `.env` file locally (add to `.gitignore`).
  - In cloud (Render.com, Neon), use service dashboards to set env vars securely.
- **Rotate credentials periodically** (monthly for development, per company policy for production).

### SQL Injection Prevention
- **Always use parameterized queries** (ORM or prepared statements).
  - ✅ Good: `db.query(User).filter(User.id == user_id).first()`
  - ❌ Bad: `db.execute(f"SELECT * FROM users WHERE id = {user_id}")`
  - FastAPI + SQLAlchemy ORM handles this automatically.

### Principle of Least Privilege
- **Create database users with minimal permissions:**
  - Ingestion Service: Write-only to `market_events` table
  - Analytics Service: Read-only from `market_events`, write to `metrics` table
  - API Service: Read-only from alerts/metrics, write to `alert_logs` table
  - **Example:**
    ```sql
    CREATE USER analytics_user PASSWORD 'xxx';
    GRANT SELECT ON market_events TO analytics_user;
    GRANT INSERT, UPDATE ON metrics TO analytics_user;
    ```

### Data Encryption
- **Sensitive columns:** Encrypt user email, API keys (if stored) at rest.
  - PostgreSQL supports `pgcrypto` extension for column-level encryption.
  - Or hash/encrypt at application level before storing.

### Database Backups
- **Enable automated backups** (Neon does this automatically).
- **Test restore procedures** to ensure backups are usable.
- **Store backups separately** from production (different region, account).

---

## 3. Message Broker Security (Kafka/Redpanda)

### Authentication
- **Secure Kafka broker:** Enable SASL authentication (username/password).
  - Upstash Kafka requires API credentials—store securely in env vars.
  - Redpanda (local) can skip auth in dev but should enable for production-like testing.

### Topic Access Control
- **Restrict producer/consumer permissions:**
  - Ingestion Service: Write to `market-data-raw` only.
  - Analytics Service: Read from `market-data-raw` only.
  - Alerts Service: Read from `market-data-raw`, write to `alerts` topic.

### Encryption in Transit
- **Use TLS/SSL for Kafka connections** (Upstash requires this).
  - Set `security.protocol=SSL` in Python Kafka client config.

### Message Retention & Cleanup
- **Configure retention policies** (e.g., keep messages for 7 days).
  - Prevents unbounded storage costs and old data exposure.
  - Upstash automatically enforces limits; set locally in Redpanda.

---

## 4. Secrets Management

### Environment Variables
- **Never commit secrets to Git:**
  - `.env` file → `.gitignore`
  - GitHub Actions secrets for CI/CD (not in workflow YAML)
  - Example secrets to protect:
    - Database credentials
    - Kafka API keys
    - Redis passwords
    - Firebase service account key
    - Binance API credentials (even if not needed for public WebSocket)

### Secrets in Cloud
- **Render.com:** Use "Environment" tab to set vars securely (not visible in logs).
- **Vercel:** Use `.env.local` + "Environment Variables" dashboard.
- **GitHub Actions:** Use "Secrets" section (encrypted, masked in logs).

### Example `.env` (Local Only)
```
DB_HOST=localhost
DB_USER=postgres
DB_PASSWORD=dev_password_only
KAFKA_BOOTSTRAP_SERVERS=redpanda:9092
REDIS_URL=redis://localhost:6379
FIREBASE_SERVICE_ACCOUNT_KEY=<json_key>
```

---

## 5. Frontend Security (React)

### XSS (Cross-Site Scripting) Prevention
- **Never use `dangerouslySetInnerHTML`** for user-controlled data.
  - React escapes content by default; rely on that.
  - If you must render HTML, sanitize with `DOMPurify` library.

### CSRF (Cross-Site Request Forgery) Protection
- **Use SameSite cookies** (FastAPI middleware sets this automatically).
- **Verify tokens on state-changing requests** (POST, PUT, DELETE).
  - Firebase handles token verification automatically.

### Dependency Vulnerabilities
- **Regularly audit dependencies:**
  ```bash
  npm audit  # Check for vulnerable packages
  npm audit fix  # Auto-fix safe issues
  ```
- **Update React, Recharts, and build tools** monthly.
- **Use GitHub Dependabot** (free) to auto-notify about vulnerabilities.

### Sensitive Data in Frontend
- **Never expose secrets in React code:**
  - ❌ Bad: `const API_KEY = "abc123"` in source
  - ✅ Good: Fetch from secure backend endpoint, use as Bearer token
  - ✅ Good: Use Firebase client SDK (manages tokens safely)

### HTTPS & CSP (Content Security Policy)
- **Vercel enforces HTTPS automatically.**
- **Set minimal CSP headers** (optional for portfolio, good practice):
  ```
  Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'
  ```

---

## 6. Logging & Error Handling

### What to Log
- **Log security events:** Failed auth attempts, unusual API usage, database errors.
- **Sanitize logs:** Never log passwords, API keys, user tokens.
- **Example:**
  ```python
  logger.info(f"User {user_id} accessed /replay")  # Good
  logger.warning(f"Failed auth for user {user_id}")  # Good
  logger.error(f"DB error: {str(error)}")  # Never include full error with creds
  ```

### What NOT to Log
- ❌ Full request/response bodies (might contain secrets)
- ❌ Database connection strings
- ❌ API keys or tokens
- ❌ User passwords or personal data

### Error Responses
- **Hide implementation details from users:**
  - ✅ Good: `{"error": "Invalid request"}`
  - ❌ Bad: `{"error": "SQL syntax error near 'password' column"}`
- **Log full errors server-side for debugging; return generic messages to client.**

---

## 7. Dependency Management

### Supply Chain Security
- **Only install trusted packages:**
  - Use official PyPI (Python) and npm (JavaScript) registries.
  - Check package downloads, GitHub stars, and maintenance status.
  - Avoid unmaintained packages (>1 year without updates).

### Vulnerability Scanning
- **Enable GitHub's built-in security scanning:**
  - Go to Settings → Security & analysis → Enable "Dependabot alerts" and "Secret scanning."
- **Scan Docker images:**
  ```bash
  docker scan ghcr.io/yourusername/api:latest
  ```

### Pin Dependencies
- **Use exact versions in production:**
  ```
  # ✅ Good (requirements.txt)
  fastapi==0.104.1
  sqlalchemy==2.0.23
  
  # ❌ Bad (too loose)
  fastapi>=0.100
  ```

---

## 8. Authentication & Authorization (Firebase)

### Firebase Best Practices
- **Keep Firebase SDK updated:** It patches security issues regularly.
- **Use Firebase Security Rules** (not applicable for this API-based approach, but good to know).
- **Verify tokens on every protected endpoint:**
  ```python
  async def verify_firebase_token(token: str) -> User:
      try:
          decoded = firebase_admin.auth.verify_id_token(token)
          return User(uid=decoded['uid'], email=decoded['email'])
      except Exception:
          raise HTTPException(status_code=401, detail="Invalid token")
  ```

### Token Expiration
- **Firebase ID tokens expire after 1 hour.**
- **Use refresh tokens** to get new ID tokens without re-authenticating.
- **Frontend handles this automatically** (Firebase SDK manages refresh).

---

## 9. Data Privacy

### User Data Minimization
- **Only collect data you need:**
  - Email + UID from Firebase (enough for auth).
  - Don't store user portfolio data unless necessary.
  - If you must, encrypt it.

### Data Retention
- **Delete old data according to policy:**
  - Market events: Keep 7 days (per decisions doc).
  - Alert logs: Keep 30 days, then archive/delete.
  - Set automatic cleanup jobs:
    ```python
    # Scheduled task to delete old events
    @app.on_event("startup")
    async def cleanup_old_data():
        scheduler.add_job(delete_old_events, 'cron', hour=2, minute=0)
    ```

### Compliance Notes
- **GDPR (if EU users):** Provide data export/deletion endpoints.

---

## 10. Monitoring & Incident Response

### What to Monitor
- **Unusual API activity:** Rate limit hits, auth failures, large data queries.
- **Service health:** Kafka lag, Redis memory usage, DB connection pool exhaustion.
- **Errors:** Deploy a simple logging dashboard (e.g., Render logs, CloudWatch free tier).

### Alerting
- **Set up basic alerts:**
  - Render.com: Deploy failures
  - GitHub Actions: CI/CD failures
  - Optional: Uptime monitor (UptimeRobot free tier) pings `/health` endpoint

### Incident Response Plan (Simple)
1. **Detect:** Monitor logs/alerts.
2. **Isolate:** Stop service if needed (disable ingestion, close API).
3. **Remediate:** Fix code, rotate secrets if exposed.
4. **Document:** Note what happened and how to prevent it.

---

## 11. Deployment Security

### Docker Security
- **Use minimal base images:**
  ```dockerfile
  FROM python:3.11-slim  # Not :latest or :bullseye
  ```
- **Don't run as root:**
  ```dockerfile
  RUN adduser --disabled-password nonroot
  USER nonroot
  ```
- **Scan images for vulnerabilities:**
  ```bash
  docker scan your-image:tag
  ```

### CI/CD Security
- **GitHub Actions secrets:**
  - Never echo secrets in logs.
  - Use `::add-mask::` to hide sensitive output.
  ```yaml
  - name: Deploy
    env:
      DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
    run: |
      echo "::add-mask::$DB_PASSWORD"
      ./deploy.sh
  ```

### Infrastructure Permissions
- **GitHub Actions:** Use least-privilege token scopes.
- **Render/Vercel:** Create dedicated service accounts (don't use personal account).
- **Container Registry:** Keep GHCR repo private until deployment.

---

## 12. Quick Security Checklist

Before deploying to production:

- [ ] All secrets stored in env vars (not in code)
- [ ] HTTPS enabled on all cloud services (automatic)
- [ ] API endpoints require authentication
- [ ] Database user has minimal permissions
- [ ] Input validation on all endpoints (Pydantic models)
- [ ] CORS restricted to known origins
- [ ] No logging of secrets or passwords
- [ ] SQL queries use parameterized statements (ORM)
- [ ] Dependencies up-to-date and scanned
- [ ] Docker image runs as non-root user
- [ ] Sensitive data encrypted at rest (or noted as future work)
- [ ] Rate limiting enabled on API
- [ ] GitHub secret scanning enabled
- [ ] Monitoring/alerting for errors set up

---

## Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/) — Common web vulnerabilities
- [FastAPI Security](https://fastapi.tiangolo.com/tutorial/security/) — Official security patterns
- [GitHub Security Hardening](https://docs.github.com/en/actions/security-guides) — CI/CD best practices
- [Firebase Security Rules](https://firebase.google.com/docs/rules) — Auth patterns
- [Django Security](https://docs.djangoproject.com/en/stable/topics/security/) — General web security (applies to FastAPI too)

---

**Last Updated:** December 2025  
**Target Audience:** Junior engineers building the Market Watcher MVP
