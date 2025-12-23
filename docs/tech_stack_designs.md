# Technical Implementation Blueprint for User Stories

## Overview: Local-First → Cloud-Smooth Architecture

The constraints are **free-tier cloud services** + **local dev/test parity** + **production-grade quality**. 

---

## File & Directory Structure

The project follows a modular, service-oriented architecture with clear separation of concerns.


### Design Principles
1. **Service Isolation:** Each service has its own dependencies, tests, and Dockerfile
2. **Shared Code:** Common utilities in `services/shared/` to avoid duplication
3. **Configuration Centralization:** All configs in `config/`, secrets in `.env`
4. **Test Co-location:** Tests live within each service for easier maintenance
5. **Documentation-First:** All major decisions documented in `docs/`

---

## User Story 1: Real-Time Market Monitoring (MtM/uPnL)

### What You Need to Build

| Component | Technical Decision | Rationale |
|-----------|-------------------|-----------|
| **Data Source** | Binance WebSocket API (cryptocurrency spot market) | Free, high-quality real-time data. No API key needed for public streams. |
| **Ingestion Service** | Python + `websockets` library | Lightweight, handles WebSocket reconnections, easy to containerize. |
| **Message Broker** | **Upstash Kafka** (free tier) | 10K messages/day. With 500ms sampling = ~7,200 msgs/hour. Limited ingestion window: 8 AM-9 AM daily (1 hour = 7,200 messages). Redpanda runs locally for dev. |
| **Backend API** | **FastAPI** (Python) | Async-native (handles WebSocket → REST efficiently), auto-generates OpenAPI docs, excellent for streaming endpoints. |
| **Real-time Push** | **Server-Sent Events (SSE)** via FastAPI | Simpler than WebSockets for one-way server→client streams. Works great with Docker/cloud. |
| **Frontend** | **React** + **Recharts** (charting library) | Industry-standard, easy Docker deployment. Recharts handles streaming updates efficiently. |
| **Containerization** | Docker Compose (local) → Individual Dockerfiles (cloud) | `docker-compose.yml` for local dev. Push images to AWS ECR Free Tier or GitHub Container Registry (GHCR) for cloud. |

### Data Flow
```
Binance WS → Ingestion Service → Redpanda (market-data-raw topic)
                                        ↓
                                  Analytics Engine (consumes topic)
                                        ↓
                                  FastAPI (SSE endpoint)
                                        ↓
                                  React Dashboard
```

---

## User Story 2: Rolling Analytics (Volatility, Drawdown)

### What You Need to Build

| Component | Technical Decision | Rationale |
|-----------|-------------------|-----------|
| **Stream Processor** | Python consumer (Kafka client) + pandas/numpy | Consume from Redpanda, calculate rolling windows in-memory. |
| **State Management** | Redis (Docker locally, Upstash Redis free tier for cloud) | Store rolling window state (last N prices) + calculated metrics. Upstash free = 10K commands/day (enough for MVP). |
| **Calculation Logic** | Pandas rolling windows (`.rolling()`) | Industry-standard for time-series. Calculate std dev (volatility) and max drawdown efficiently. |

### Key Technical Decisions
- **Window Size:** 60 data points (= 30 seconds at 500ms sampling)
- **Storage:** Redis stores:
  - `price_window:{symbol}` → List of last 60 prices
  - `metrics:{symbol}` → JSON of `{volatility, mdd, timestamp}`

---

## User Story 3: Alerting on Derived Metrics

### What You Need to Build

| Component | Technical Decision | Rationale |
|-----------|-------------------|-----------|
| **Alert Rules Engine** | Python (same process as Analytics Engine) | Read thresholds from config file. When metric exceeds threshold → emit alert event. |
| **Alert Storage** | PostgreSQL (Docker locally, **Neon** free tier for cloud) | Neon = 0.5GB free, serverless Postgres. Store alert history for replay. |
| **Alert Delivery** | Push to Redis Pub/Sub → FastAPI listens → SSE to frontend | Real-time alerts without polling. Redis Pub/Sub is free-tier friendly. |
| **Alert Schema** | `{alert_id, symbol, metric, threshold, timestamp, trigger_value}` | Must store enough context for replay. |

### Why Not Email/SMS?
Email (SendGrid free tier) requires external dependency. Keep MVP simple: in-app alerts only.

---

## User Story 4: Event Replay

### What You Need to Build

| Component | Technical Decision | Rationale |
|-----------|-------------------|-----------|
| **Time-Series DB** | **PostgreSQL with TimescaleDB extension** | Hybrid approach: use Postgres (you already need it for alerts) + TimescaleDB for efficient time-range queries. Free on Neon or locally. |
| **Data Retention** | Store raw market data for **7 days** (configurable) | Balance storage costs vs. replay capability. 7 days = ~1.2M events per symbol (manageable on free tier). |
| **Replay API** | FastAPI endpoint: `GET /replay?alert_id={id}` | Query TimescaleDB for events ±5 minutes around alert timestamp. Return JSON. |
| **Frontend Replay** | React component with Recharts line chart | Simple time-series chart with alert marker. |

### Schema Design
```sql
-- TimescaleDB hypertable
CREATE TABLE market_events (
    time TIMESTAMPTZ NOT NULL,
    symbol TEXT NOT NULL,
    price NUMERIC NOT NULL,
    volume NUMERIC NOT NULL
);
SELECT create_hypertable('market_events', 'time');
```

---

## Containerization & Deployment Strategy

### Local Development
```yaml
# docker-compose.yml
services:
  redpanda:
    image: vectorized/redpanda
    ports: [9092:9092]
  
  redis:
    image: redis:alpine
    ports: [6379:6379]
  
  postgres:
    image: timescale/timescaledb:latest-pg15
    ports: [5432:5432]
  
  ingestion:
    build: ./services/ingestion
    depends_on: [redpanda]
  
  analytics:
    build: ./services/analytics
    depends_on: [redpanda, redis, postgres]
  
  api:
    build: ./services/api
    ports: [8000:8000]
    depends_on: [redis, postgres]
  
  frontend:
    build: ./frontend
    ports: [3000:3000]
```

**Run locally:** `docker-compose up`

---

### Cloud Deployment (Free Tier Strategy)

**⚠️ Important:** With Upstash Kafka's 10K messages/day limit and 500ms sampling (2 msgs/sec = 7,200 msgs/hour), **data ingestion is active only during peak market hours: 8 AM - 9 AM UTC** to stay within budget. Historical replay data is stored in TimescaleDB for testing/analysis outside this window.

| Service | Local | Cloud Free Tier |
|---------|-------|----------------|
| **Message Broker** | Redpanda (Docker) | **Upstash Kafka** (10K msgs/day, ingestion 8 AM-9 AM) |
| **Redis** | Redis (Docker) | **Upstash Redis** (10K commands/day) |
| **PostgreSQL** | TimescaleDB (Docker) | **Neon** (0.5GB free) |
| **Backend API** | FastAPI (Docker) | **Render.com** (free tier) or **Railway** (free tier) |
| **Frontend** | React (Docker) | **Vercel** or **Netlify** (free static hosting) |
| **Container Registry** | N/A | **GitHub Container Registry (GHCR)** (free) |

### Cloud Deployment
```
GitHub Actions (CI/CD)
  → Build Docker images
  → Push to GHCR
  → Deploy to Render.com (backend services)
  → Deploy to Vercel (frontend)
```

---

## Cloud Deployment Architecture

**⚠️ Important:** With Upstash Kafka's 10K messages/day limit and 500ms sampling (2 msgs/sec = 7,200 msgs/hour), **data ingestion is active only during peak market hours: 8 AM - 9 AM UTC** to stay within budget. Historical replay data is stored in TimescaleDB for testing/analysis outside this window.

```
┌─────────────────────────────────────────────────────┐
│              Daily Ingestion (8-9 AM UTC)           │
│  Binance WS → Python Ingestion → Upstash Kafka      │
└──────────────────┬──────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────────────┐
│         Throughout Day (All timezones)               │
│  Upstash Kafka → Analytics Engine → Upstash Redis    │
│                                          ↓            │
│                                   Neon Postgres       │
└──────────────────┬───────────────────────────────────┘
                   ↓
     ┌─────────────┴──────────────┐
     ↓                            ↓
 [Render FastAPI]        [Vercel React]
```

**Key Note:** All services use public endpoints (suitable for portfolio, not production).

---

## CI/CD Pipeline (GitHub Actions)

### Local Testing
```yaml
# .github/workflows/test.yml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run docker-compose tests
        run: docker-compose -f docker-compose.test.yml up --abort-on-container-exit
```

### Cloud Deployment
```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build and push to GHCR
        run: |
          docker build -t ghcr.io/${{ github.repository }}/api:latest ./services/api
          docker push ghcr.io/${{ github.repository }}/api:latest
      - name: Deploy to Render.com
        run: |
          curl -X POST https://api.render.com/deploy/srv-xxxxx
```

---

## Free-Tier Budget Reality Check

| Resource | Free Tier Limit | Your Usage Estimate | Verdict |
|----------|----------------|---------------------|---------|
| Upstash Redis | 10K commands/day | ~5K/day (alerts + metrics) | ✅ Safe |
| Neon Postgres | 0.5GB storage | ~100MB (7 days raw data) | ✅ Safe |
| Upstash Kafka | 10K msgs/day | ~7.2K/day (1 hour ingestion) | ✅ Safe |
| Render.com | 750 compute hours/month | FastAPI backend | ✅ Safe |
| Vercel | 100GB bandwidth/month | <1GB (lightweight React app) | ✅ Safe |
| GitHub Actions | 2000 CI/CD minutes/month | ~50 mins/month (deploy on merge) | ✅ Safe |

**Total Cost: $0/month** (with constrained usage)

---

## Ingestion Strategy: Time-Window Optimization

### Calculation
- **Upstash Kafka limit:** 10,000 messages/day
- **Sampling rate:** 500ms intervals = 2 messages/second per symbol
- **Single symbol ingestion time:** 10,000 msgs ÷ (2 msgs/sec × 3600 sec/hour) = **~1.4 hours/day**
- **MVP approach:** 1 hour window (8 AM - 9 AM UTC) = **7,200 messages/day** ✅

### Implementation
1. **Ingestion Service** runs on schedule (cron job):
   - Start at 8:00 AM UTC: Connect to Binance WebSocket
   - Ingest market data for exactly 1 hour
   - Stop at 9:00 AM UTC: Close connection
   - Publish to Upstash Kafka topic

2. **Analytics Engine:**
   - Runs continuously throughout the day
   - Reads from Kafka during ingestion window
   - Re-processes stored historical data for testing/analysis outside window

3. **Replay Data:**
   - All ingested data (from 8-9 AM) persisted to TimescaleDB
   - Available for replay queries anytime during the day
   - 7-day rolling window = ~50K messages total storage ✅

### Why This Works
- **Real data:** 1 hour of real Binance market data per day
- **Testing:** Use replay data + simulated streams for testing/development outside 8-9 AM window
- **Portfolio value:** Shows understanding of cost optimization + time-series data management
- **Scalability ready:** If budget increases, just extend window (e.g., 7 AM - 4 PM = 9 hours)

---

## Tech Stack Summary

```
Frontend:     React + Recharts + Vercel
Backend API:  FastAPI + Python + Render.com
Stream:       Redpanda (local) + Upstash Kafka (cloud)
Cache:        Upstash Redis
Database:     Neon (TimescaleDB-compatible Postgres)
CI/CD:        GitHub Actions → GHCR → Render.com/Vercel
Local Dev:    Docker Compose
```

---

## Testing Strategy

### Unit Tests (Pytest)
```python
# tests/analytics/test_metrics.py
def test_volatility_calculation():
    prices = [100, 101, 99, 102, 98]
    vol = calculate_volatility(prices, window=5)
    assert vol > 0

def test_alert_trigger():
    metric = 5.2  # volatility %
    threshold = 5.0
    assert should_alert(metric, threshold) == True
```

### Integration Tests
- Kafka producer → consumer → metrics calculation flow
- Metrics → Redis storage → API retrieval
- Alert trigger → database persistence
- SSE endpoint returns real-time data

### E2E Tests
- Simulated market data through full pipeline
- Alert trigger → storage → frontend notification
- Event replay endpoint returns correct data

**Target Coverage:** 70%+ (prioritize critical paths: metrics calculation, alert logic, replay queries)

---

## Next Steps (Implementation Order)

1. ✅ Set up local `docker-compose.yml` with Redpanda + Redis + Postgres
2. ✅ Build Ingestion Service (Binance WS → Redpanda, scheduled for 8-9 AM UTC)
3. ✅ Build Analytics Engine (consume Kafka → calculate metrics → store in Redis)
4. ✅ Build FastAPI backend with SSE endpoint (stream metrics to frontend)
5. ✅ Build React dashboard (price chart + portfolio metrics + alert log)
6. ✅ Implement alert storage (Postgres) + alert triggering logic
7. ✅ Implement replay API + replay UI component
8. ✅ Add comprehensive testing (unit + integration + E2E)
9. ✅ Set up CI/CD pipeline (GitHub Actions)
10. ✅ Deploy to Render.com (backend) + Vercel (frontend)

**Estimated Timeline:** 4-5 weeks part-time (assuming 10-12 hrs/week)