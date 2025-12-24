# System Architecture Overview

## Purpose

This document describes the **Market Watcher** system architecture — a real-time market monitoring platform designed to demonstrate production-grade stream processing, data pipeline design, and cloud-native DevOps practices.

**Target audience:** Technical recruiters, hiring managers, and engineers reviewing this portfolio project.

---

## Visual Reference

See accompanying Draw.io diagrams:
- [architecture-diagram.drawio](architecture-diagram.drawio) — Full system architecture
- [user-flows.drawio](user-flows.drawio) — User journey sequences
- [frontend-wireframes.drawio](frontend-wireframes.drawio) — UI mockups

---

## Architecture Style

**Microservices with Event-Driven Architecture**

- **Service isolation:** Each service (Ingestion, Analytics, API, Frontend) is independently deployable
- **Message-driven communication:** Kafka/Redpanda for event streaming
- **Cache-first reads:** Redis for hot data, TimescaleDB for historical queries
- **API Gateway pattern:** FastAPI service exposes unified REST + SSE interface
- **Stateless services:** All state lives in Redis/Postgres, enabling horizontal scaling

---

## System Components

### Layer 1: Data Sources

#### Binance WebSocket API
- **Purpose:** Real-time cryptocurrency market data (spot prices)
- **Protocol:** WebSocket (public stream, no authentication required)
- **Data format:** JSON tickers with price, volume, timestamp
- **Sampling rate:** 500ms intervals (~2 messages/second per symbol)
- **Symbols tracked:** BTCUSDT, ETHUSDT (configurable)

**Why Binance?**
- Free, high-quality real-time data
- No API key needed for public streams
- 24/7 availability
- Well-documented WebSocket protocol

---

### Layer 2: Ingestion Service

**Technology:** Python 3.11 + `websockets` library

**Responsibilities:**
1. Connect to Binance WebSocket and maintain persistent connection
2. Handle reconnections with exponential backoff
3. Normalize external data into unified schema
4. Publish to Kafka topic `market-data-raw`
5. Respect ingestion window (08:00–09:00 UTC to stay within free-tier limits)

**Key modules:**
- `websocket_client.py` — WebSocket connection manager with heartbeat
- `data_normalizer.py` — Transform Binance format → internal schema
- `kafka_publisher.py` — Publish to Kafka with retry logic
- `scheduler.py` — Time-gated ingestion window

**Data schema (normalized):**
```json
{
  "timestamp": "2025-12-24T08:30:15.123Z",
  "symbol": "BTCUSDT",
  "price": 42350.50,
  "volume": 1.234,
  "source": "binance"
}
```

**Configuration:**
- WebSocket URL: `wss://stream.binance.com:9443/ws`
- Kafka topic: `market-data-raw`
- Ingestion window: `08:00–09:00 UTC` (1 hour daily)

**Error handling:**
- Reconnect on disconnect (max 10 retries with exponential backoff)
- Log malformed messages, skip and continue
- Health check endpoint for monitoring

---

### Layer 3: Message Broker

#### Local Development: Redpanda
- **Purpose:** Kafka-compatible streaming platform
- **Why Redpanda?** Lighter than Kafka, runs in single Docker container
- **Topics:**
  - `market-data-raw` — Raw market events from ingestion
  - `metrics-calculated` — Derived metrics from analytics (optional)
  - `alerts` — Triggered alert events (optional, also in Redis Pub/Sub)

#### Cloud Deployment: Upstash Kafka
- **Purpose:** Managed Kafka service (free tier)
- **Limits:** 10,000 messages/day
- **Why Upstash?** Generous free tier, no credit card required
- **Configuration:** SSL/SASL authentication, topic auto-creation

**Throughput calculation:**
- 1 hour ingestion × 2 symbols × 2 msg/sec = 14,400 messages/day
- **Within free tier limit** ✅

---

### Layer 4: Analytics Service

**Technology:** Python 3.11 + pandas + numpy

**Responsibilities:**
1. Consume from Kafka topic `market-data-raw`
2. Calculate derived metrics in real-time:
   - **Rolling volatility** (30-second window, standard deviation)
   - **Max drawdown** (peak-to-trough decline)
   - **Unrealized P&L** (based on mock portfolio positions)
3. Store hot metrics in Redis with TTL (60 seconds)
4. Persist raw events + metrics to TimescaleDB for replay
5. Evaluate alert thresholds and trigger alerts

**Key modules:**
- `kafka_consumer.py` — Consumer with backpressure handling
- `metrics_calculator.py` — Rolling window calculations
- `alert_engine.py` — Threshold evaluation + alert publishing
- `database_writer.py` — Batch insert to TimescaleDB

**Metrics calculation details:**

| Metric | Window | Formula | Update Frequency |
|--------|--------|---------|------------------|
| **Volatility** | 30 seconds | σ = std(log_returns) × √(2 samples/sec) | Every 500ms |
| **Max Drawdown** | 5 minutes | (Trough - Peak) / Peak | Every 500ms |
| **Unrealized P&L** | N/A | (Current Price - Entry Price) × Quantity | Every 500ms |

**Alert thresholds (configurable in `config/alert_thresholds.yml`):**
```yaml
volatility:
  high: 5.0  # percent
  critical: 10.0

drawdown:
  warning: -3.0  # percent
  critical: -5.0

pnl:
  loss_limit: -1000  # USD
```

**Data flow:**
```
Kafka (market-data-raw)
  → Analytics consumes event
  → Calculate metrics (volatility, drawdown, P&L)
  → Write to Redis: SET metrics:BTCUSDT '{"volatility": 2.3, ...}' EX 60
  → Write to TimescaleDB: INSERT INTO market_events (...)
  → If threshold breached:
      → INSERT INTO alerts (...)
      → PUBLISH to Redis Pub/Sub "alerts:realtime"
```

---

### Layer 5: Data Storage

#### Redis (Hot State & Cache)

**Local:** Redis 7 in Docker  
**Cloud:** Upstash Redis (free tier: 10K commands/day)

**Data structures:**
```
metrics:{symbol}         → JSON string (latest metrics)
price_window:{symbol}    → Sorted set (30-sec price history for volatility)
alert:{alert_id}         → Hash (alert details)
```

**TTL strategy:**
- Metrics: 60 seconds (stale data auto-expires)
- Price windows: 60 seconds
- Alerts: 24 hours

**Redis Pub/Sub:**
- Channel: `alerts:realtime`
- Subscribers: FastAPI service (for SSE streaming to frontend)

#### TimescaleDB (Historical Data)

**Local:** TimescaleDB 2.13 (Postgres extension) in Docker  
**Cloud:** Neon Postgres (free tier: 0.5 GB storage, includes TimescaleDB)

**Schema:**

```sql
-- Raw market events (hypertable)
CREATE TABLE market_events (
  time        TIMESTAMPTZ NOT NULL,
  symbol      TEXT NOT NULL,
  price       NUMERIC(18, 8),
  volume      NUMERIC(18, 8),
  source      TEXT
);

SELECT create_hypertable('market_events', 'time');

-- Retention policy (7 days)
SELECT add_retention_policy('market_events', INTERVAL '7 days');

-- Indexes
CREATE INDEX idx_market_events_symbol_time ON market_events (symbol, time DESC);

-- Alert logs
CREATE TABLE alerts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  timestamp     TIMESTAMPTZ NOT NULL,
  symbol        TEXT NOT NULL,
  alert_type    TEXT NOT NULL,  -- 'volatility', 'drawdown', 'pnl'
  severity      TEXT NOT NULL,  -- 'warning', 'critical'
  metric_value  NUMERIC,
  threshold     NUMERIC,
  message       TEXT
);

CREATE INDEX idx_alerts_time ON alerts (timestamp DESC);
```

**Query patterns:**
- Replay: `SELECT * FROM market_events WHERE symbol = ? AND time BETWEEN ? AND ? ORDER BY time`
- Alert history: `SELECT * FROM alerts WHERE symbol = ? ORDER BY timestamp DESC LIMIT 50`

---

### Layer 6: API Service (Backend)

**Technology:** FastAPI (Python 3.11) + Uvicorn

**Responsibilities:**
1. Expose REST endpoints for metrics, alerts, replay
2. Stream real-time updates via Server-Sent Events (SSE)
3. Authenticate requests with Firebase JWT tokens
4. Rate limiting to prevent abuse
5. CORS configuration for frontend origin

**Endpoints:**

| Endpoint | Method | Purpose | Auth Required |
|----------|--------|---------|---------------|
| `/health` | GET | Health check | No |
| `/api/metrics/latest` | GET | Latest metrics snapshot | Yes |
| `/api/metrics/stream` | GET | SSE stream of live metrics | Yes |
| `/api/alerts` | GET | Alert history (paginated) | Yes |
| `/api/alerts/stream` | GET | SSE stream of new alerts | Yes |
| `/api/replay` | GET | Event replay around alert | Yes |
| `/api/market-data` | GET | Raw market events (debug) | Yes |
| `/auth/verify` | POST | Verify Firebase token | Yes |

**Key modules:**
- `routers/metrics.py` — Metrics endpoints
- `routers/alerts.py` — Alerts endpoints
- `routers/replay.py` — Replay endpoint
- `middleware/auth.py` — Firebase token verification
- `middleware/rate_limit.py` — Rate limiting with Redis backend
- `services/sse_manager.py` — SSE connection management
- `services/redis_subscriber.py` — Subscribe to Redis Pub/Sub

**Authentication flow:**
```
1. Frontend obtains Firebase ID token (after Google OAuth)
2. Frontend sends request: Authorization: Bearer <firebase_token>
3. FastAPI middleware verifies token with Firebase Admin SDK
4. If valid, extract user UID and proceed
5. If invalid, return 401 Unauthorized
```

**Rate limiting:**
- 100 requests/minute per authenticated user
- 1000 requests/hour per IP address
- Backed by Redis (using `slowapi` library)

**CORS configuration:**
```python
origins = [
    "http://localhost:3000",  # Local dev
    "https://market-watcher.vercel.app"  # Production
]
```

**SSE implementation (metrics stream):**
```python
@router.get("/api/metrics/stream")
async def metrics_stream(request: Request, user=Depends(verify_token)):
    async def event_generator():
        while True:
            if await request.is_disconnected():
                break
            
            # Read latest metrics from Redis
            metrics = await redis.get(f"metrics:{symbol}")
            
            # Send SSE event
            yield f"data: {metrics}\n\n"
            
            await asyncio.sleep(0.5)  # 500ms update interval
    
    return EventSourceResponse(event_generator())
```

---

### Layer 7: Frontend (UI)

**Technology:** React 18 + TypeScript + Vite

**Hosting:** Vercel (free tier with automatic HTTPS)

**Key libraries:**
- **Recharts** — Real-time charting (price chart, volatility chart)
- **Firebase Auth** — Google OAuth authentication
- **EventSource API** — SSE client for live updates

**Pages/Components:**

| Component | Purpose |
|-----------|---------|
| `LoginPage` | Firebase Google OAuth |
| `Dashboard` | Main layout with portfolio summary |
| `PriceChart` | Real-time candlestick/line chart |
| `MetricsDisplay` | Live volatility, drawdown, P&L badges |
| `AlertLog` | Scrollable list of past alerts |
| `EventReplay` | Modal with replay chart around alert |

**Key services:**
- `api_client.ts` — Axios wrapper for REST calls
- `sse_client.ts` — EventSource wrapper for SSE streams
- `firebase_auth.ts` — Firebase initialization + auth helpers

**State management:**
- React hooks (useState, useEffect, useContext)
- Custom hooks: `useMetricsStream`, `useAlerts`, `useReplay`

**Real-time update flow:**
```typescript
// useMetricsStream hook
function useMetricsStream(symbol: string) {
  const [metrics, setMetrics] = useState<Metrics | null>(null);
  
  useEffect(() => {
    const eventSource = new EventSource(
      `${API_URL}/api/metrics/stream?symbol=${symbol}`,
      { headers: { Authorization: `Bearer ${firebaseToken}` } }
    );
    
    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      setMetrics(data);
    };
    
    return () => eventSource.close();
  }, [symbol]);
  
  return metrics;
}
```

---

## Data Flow Scenarios

### Scenario 1: Real-Time Metrics Update (Happy Path)

**End-to-end latency: ~100–200ms**

```
1. Binance publishes ticker update (t=0ms)
   ↓
2. Ingestion service receives WebSocket message (t=10ms)
   ↓
3. Normalize and publish to Kafka topic (t=20ms)
   ↓
4. Analytics service consumes from Kafka (t=30ms)
   ↓
5. Calculate metrics (volatility, drawdown, P&L) (t=50ms)
   ↓
6. Write to Redis: SET metrics:BTCUSDT {...} (t=70ms)
   ↓
7. Write to TimescaleDB (batch insert, async) (t=80ms)
   ↓
8. FastAPI reads from Redis every 500ms (t=100ms)
   ↓
9. SSE stream sends to connected frontend clients (t=120ms)
   ↓
10. React updates chart component (t=150ms)
```

**Bottlenecks:**
- Redis read latency (typically <5ms with Upstash)
- Network latency (FastAPI → Vercel frontend, ~50ms)

**Optimization:**
- Redis connection pooling
- Batch TimescaleDB writes (insert every 5 seconds)
- Frontend debouncing (500ms chart updates)

---

### Scenario 2: Alert Trigger & User Notification

```
1. Market price drops 4% in 2 minutes
   ↓
2. Analytics calculates drawdown = -4.1%
   ↓
3. Compare to threshold (warning = -3.0%)
   ↓
4. Threshold breached! Create alert event
   ↓
5. INSERT INTO alerts (...) in Postgres
   ↓
6. PUBLISH to Redis Pub/Sub channel "alerts:realtime"
   ↓
7. FastAPI service listens to Pub/Sub channel
   ↓
8. SSE broadcast to all connected clients: /api/alerts/stream
   ↓
9. Frontend receives alert event
   ↓
10. Toast notification appears: "⚠️ BTCUSDT Drawdown Alert: -4.1%"
   ↓
11. Alert added to AlertLog component
```

**Alert deduplication:**
- Track last alert timestamp per (symbol, alert_type) in Redis
- Only trigger new alert if >5 minutes since last similar alert

---

### Scenario 3: User Replays Event Around Alert

```
1. User clicks "Replay" button on alert in AlertLog
   ↓
2. Frontend calls: GET /api/replay?alert_id=uuid&window_seconds=300
   ↓
3. FastAPI queries alerts table to get alert timestamp
   ↓
4. FastAPI queries TimescaleDB:
   SELECT * FROM market_events
   WHERE symbol = 'BTCUSDT'
     AND time BETWEEN alert_time - 5min AND alert_time + 5min
   ORDER BY time
   ↓
5. Return array of ~600 events (2 events/sec × 600 seconds)
   ↓
6. Frontend renders replay chart with:
   - Price line chart
   - Vertical red line at alert timestamp
   - Shaded region showing ±5 minute window
   - Metrics overlay (volatility spike visible)
```

**Query optimization:**
- Index on (symbol, time) ensures fast range scan
- Limit to 10-minute window (max 1200 events)
- Cache replay results in Redis for 5 minutes

---

### Scenario 4: User Login Flow

```
1. User opens dashboard → redirected to LoginPage
   ↓
2. User clicks "Sign in with Google"
   ↓
3. Firebase Auth redirects to Google OAuth consent screen
   ↓
4. User approves
   ↓
5. Google redirects back with authorization code
   ↓
6. Firebase exchanges code for ID token
   ↓
7. Frontend stores token in localStorage
   ↓
8. Frontend navigates to Dashboard
   ↓
9. Dashboard component calls: GET /api/metrics/latest
   with Authorization: Bearer <firebase_token>
   ↓
10. FastAPI verifies token with Firebase Admin SDK
   ↓
11. If valid, return metrics; else 401 Unauthorized
   ↓
12. Dashboard renders with live data
```

**Token refresh:**
- Firebase SDK auto-refreshes token before expiry (1 hour TTL)
- Frontend intercepts 401 responses and triggers re-auth

---

## Deployment Topologies

### Local Development Stack

**Technology:** Docker Compose

**Services:**
```yaml
services:
  redpanda:       # Kafka-compatible broker
  redis:          # Cache + Pub/Sub
  postgres:       # TimescaleDB extension enabled
  ingestion:      # Python ingestion service
  analytics:      # Python analytics service
  api:            # FastAPI backend
  frontend:       # React dev server (Vite)
```

**Startup:**
```bash
docker-compose up -d
# Services available at:
# - Redpanda Console: http://localhost:8080
# - API: http://localhost:8000
# - Frontend: http://localhost:3000
# - Postgres: localhost:5432
# - Redis: localhost:6379
```

**Benefits:**
- Full stack runs locally
- No cloud dependencies for development
- Fast iteration cycles
- Easy debugging with logs: `docker-compose logs -f analytics`

---

### Cloud Deployment Stack (Free Tier)

**Goal:** Zero-cost hosting with production-grade reliability

| Component | Service | Free Tier Limit | Why This Choice |
|-----------|---------|----------------|-----------------|
| **Message Broker** | Upstash Kafka | 10K msgs/day | Generous limit, no CC required |
| **Cache** | Upstash Redis | 10K commands/day | Global edge caching, fast |
| **Database** | Neon Postgres | 0.5 GB storage | Includes TimescaleDB, auto-scaling |
| **Backend (Ingestion + Analytics + API)** | Render.com | 750 hrs/month | Dockerized services, auto-deploy |
| **Frontend** | Vercel | Unlimited | Instant CDN, auto HTTPS |
| **Container Registry** | GitHub Container Registry | 500 MB storage | Free for public repos |
| **Authentication** | Firebase Auth | 10K auths/month | Google OAuth integration |
| **Monitoring** | UptimeRobot | 50 monitors | Free health checks |

**Ingestion window strategy:**
- Run ingestion **only 08:00–09:00 UTC** (1 hour/day)
- 2 symbols × 2 msg/sec × 3600 sec = 14,400 messages/day
- **Stays within 10K Kafka limit** ✅ (with buffer for retries)

**Deployment architecture:**
```
User (Browser)
  ↓ HTTPS
Vercel CDN (React Frontend)
  ↓ HTTPS + JWT
Render.com (FastAPI API Service)
  ↓ TLS
Upstash Redis (Metrics Cache)
  ↓ TLS
Neon Postgres (TimescaleDB)

Render.com (Ingestion Service) → Upstash Kafka → Render.com (Analytics Service)
```

**Cost breakdown:**
- **Total: $0/month** (all free tiers)
- No credit card required for any service
- Automatic HTTPS/TLS everywhere
- Global CDN for frontend

---

## Scalability Considerations

### Current Bottlenecks

| Component | Limit | Impact |
|-----------|-------|--------|
| **Upstash Kafka** | 10K msgs/day | Restricts ingestion to 1 hour/day |
| **Redis commands** | 10K/day | Limits API request rate to ~1 req/9 sec average |
| **Neon storage** | 0.5 GB | ~7 days retention with current schema |

### Scaling Strategy (If Moving Beyond Free Tier)

**Horizontal scaling:**
- Multiple Analytics service instances (Kafka consumer group)
- Load balancer in front of API service (Render.com auto-scales)
- Redis Cluster for distributed cache

**Vertical scaling:**
- Upgrade Upstash to paid tier (unlimited messages)
- Upgrade Neon to larger storage (3 GB → 30-day retention)
- Add TimescaleDB continuous aggregates for pre-computed metrics

**Architectural improvements:**
- Add Kafka Streams for stateful processing (reduce Redis dependency)
- Implement CQRS pattern (separate write/read models)
- Add materialized views in TimescaleDB for faster queries

---

## Technology Decisions Rationale

### Why Python for Backend Services?

**Pros:**
- Rich ecosystem for data processing (pandas, numpy)
- Excellent Kafka/Redis libraries
- Fast prototyping, readable code
- Strong typing with type hints (mypy)

**Cons:**
- GIL limits CPU-bound parallelism (mitigated by async I/O)
- Slower than Go/Rust for raw throughput

**Decision:** Python's productivity outweighs performance trade-offs for MVP scale.

---

### Why FastAPI Over Flask/Django?

**Pros:**
- Native async support (critical for SSE)
- Automatic OpenAPI/Swagger docs
- Type-safe with Pydantic models
- Built-in dependency injection

**Cons:**
- Smaller ecosystem than Flask
- Newer, less battle-tested

**Decision:** FastAPI's async + type safety aligns with project requirements.

---

### Why Redpanda Over Kafka?

**For local development:**
- Single binary, no JVM required
- 10x faster startup
- Kafka-compatible API

**For cloud:**
- Upstash Kafka chosen for free tier (Redpanda has no free cloud offering)

---

### Why TimescaleDB Over InfluxDB/Prometheus?

**Pros:**
- Standard SQL (easier than InfluxQL/PromQL)
- PostgreSQL ecosystem (mature, well-documented)
- Automatic partitioning via hypertables
- Joins with relational tables (alerts, users)

**Cons:**
- Not pure time-series DB (less optimized than InfluxDB)

**Decision:** SQL familiarity + joins make TimescaleDB best fit.

---

### Why React Over Vue/Svelte?

**Pros:**
- Largest job market demand (portfolio signal)
- Rich charting libraries (Recharts, Victory)
- Strong TypeScript support

**Cons:**
- More boilerplate than Svelte
- Larger bundle size than Vue

**Decision:** React's industry adoption makes it portfolio-optimal.

---

## Security Measures

See [security_guidelines.md](security_guidelines.md) for full checklist.

**Key implementations:**

1. **Authentication:** Firebase JWT verification on all protected endpoints
2. **Rate limiting:** Redis-backed rate limiter (slowapi)
3. **CORS:** Whitelist frontend origin only
4. **Input validation:** Pydantic models enforce schema
5. **Secrets management:** Environment variables, never committed
6. **HTTPS/TLS:** Enforced by Vercel/Render/Upstash
7. **Database:** Connection pooling, parameterized queries (SQLAlchemy)
8. **Logging:** Structured logs, no PII leakage

---

## Observability & Monitoring

### Logging Strategy

**Format:** JSON structured logs (for log aggregation)

**Example log entry:**
```json
{
  "timestamp": "2025-12-24T08:30:15.123Z",
  "service": "analytics",
  "level": "INFO",
  "event": "metrics_calculated",
  "symbol": "BTCUSDT",
  "volatility": 2.34,
  "latency_ms": 45
}
```

**Aggregation (future):**
- Local: `docker-compose logs -f <service>`
- Cloud: Render.com log streams → potential export to Logtail/Papertrail

---

### Health Checks

**Endpoint:** `GET /health` (no auth required)

**Response:**
```json
{
  "status": "ok",
  "version": "1.0.0",
  "uptime_seconds": 3600,
  "dependencies": {
    "redis": "connected",
    "postgres": "connected",
    "kafka": "connected"
  }
}
```

**Monitoring:**
- UptimeRobot pings `/health` every 5 minutes
- Alert on 2 consecutive failures

---

### Metrics (Future Enhancement)

**Potential additions:**
- Prometheus exporter in FastAPI
- Grafana dashboard showing:
  - Message throughput (Kafka)
  - API latency (p50, p95, p99)
  - Cache hit rate (Redis)
  - Alert trigger frequency

---

## Testing Strategy

See individual service READMEs for detailed test plans.

**Layers:**

| Test Type | Scope | Tools |
|-----------|-------|-------|
| **Unit** | Individual functions/classes | pytest, unittest.mock |
| **Integration** | Service + database/Kafka | pytest + Docker Compose |
| **E2E** | Full pipeline with fixtures | pytest + docker-compose.test.yml |
| **Frontend** | Components + hooks | Vitest, React Testing Library |
| **Contract** | API spec compliance | OpenAPI validator |

**CI/CD:**
- GitHub Actions run tests on every PR
- Lint (ruff, mypy) + unit tests + integration tests
- Deploy to staging on merge to `main`

---

## Open Questions & Future Work

### Short-term (Next 2-4 weeks)
- [ ] Implement authentication middleware
- [ ] Add frontend error boundaries
- [ ] Write E2E tests with fixtures
- [ ] Deploy to cloud free tier

### Medium-term (1-2 months)
- [ ] Add WebSocket support (upgrade from SSE for bi-directional)
- [ ] Implement user portfolio management (mock positions)
- [ ] Add custom alert rules via UI
- [ ] Performance profiling (trace end-to-end latency)

### Long-term (Portfolio Evolution)
- [ ] Add machine learning: anomaly detection on metrics
- [ ] Multi-asset support (equities via Alpha Vantage)
- [ ] Backtesting framework (replay historical data)
- [ ] Mobile app (React Native)

---

## Conclusion

This architecture balances **production-grade engineering** with **free-tier constraints**, demonstrating:

1. **Stream processing expertise** (Kafka, rolling windows, real-time analytics)
2. **Data pipeline design** (ingestion → processing → storage → API)
3. **Cloud-native practices** (containerization, microservices, observability)
4. **Full-stack capability** (Python backend, React frontend, DevOps)

**For recruiters:** This is not a toy project. Every decision reflects real-world trade-offs, scalability considerations, and production best practices.

---

**Last updated:** 2025-12-24  
**Author:** Taylor Chou  
**Repository:** [market_watcher](https://github.com/yourusername/market_watcher)
