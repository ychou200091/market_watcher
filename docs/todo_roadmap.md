# Market Watcher Delivery Plan

A milestone-based roadmap with checkboxes and suggested tests at each step. Follow in order; each milestone should be shippable and demoable.

## Milestone 0 — Environment & Repo Hygiene
- [ ] Copy `.env.example` → `.env` and fill Kafka/Redis/Postgres/Firebase placeholders
- [ ] Install toolchain (Python 3.11+, Node 18+, Docker 20+); verify `docker --version`, `python --version`, `node --version`
- [ ] Add base dev tools configs (`.gitignore`, `requirements.txt` pinning, `pytest.ini`, `mypy.ini`, `ruff/flake8` config)
- [ ] Create root `config/` placeholders (`alert_thresholds.yml`, `ingestion_schedule.yml`, `logging_config.yml`) with sane defaults
- [ ] Add `.github/workflows/test.yml` stub to run lint + unit tests
- [ ] Smoke test: `docker-compose config` to ensure compose file parses

## Milestone 1 — Shared Infrastructure Layer (services/shared)
- [ ] Implement `kafka_client.py` (producer/consumer helpers; SSL flags for Upstash)
- [ ] Implement `redis_client.py` (connection pool + health check)
- [ ] Implement `database_connection.py` (Timescale/Postgres SQLAlchemy engine + session helper)
- [ ] Implement `logging_setup.py` (structlog or stdlib logging with JSON formatter)
- [ ] Add `exceptions.py` with typed errors (e.g., `KafkaConnectionError`, `InvalidPayloadError`)
- [ ] Tests: unit tests for each client (mocks) and connection smoke tests gated by env var
- [ ] Verification: run `pytest services/shared/tests` (add minimal tests) and `python -m services.shared.kafka_client --help`-style quick check

## Milestone 2 — Database & Schema
- [ ] Finalize `db/schema.sql` for `market_events`, `alerts`, `metrics` hypertables; include indexes and retention policy
- [ ] Add seed script `scripts/seed_test_data.py` to load `tests/fixtures/sample_market_data.json`
- [ ] Add migration note or `make`/script to apply schema via `psql`
- [ ] Tests: integration test hitting local Timescale container applying schema + inserting sample rows
- [ ] Verification: `docker-compose up postgres` then `psql -f db/schema.sql` succeeds; sample query returns rows

## Milestone 3 — Ingestion Service
- [ ] Flesh out `services/ingestion/` (websocket client for Binance, reconnect logic, scheduler for 8–9 AM UTC window)
- [ ] Implement `data_normalizer.py` producing unified JSON schema
- [ ] Implement `kafka_publisher.py` using shared Kafka helper; topic `market-data-raw`
- [ ] Add `scheduler.py` to gate ingestion window (config-driven)
- [ ] Tests: unit tests for normalizer/publisher; integration test `test_websocket_to_kafka` with stub WS server
- [ ] Verification: run ingestion locally against sample stream; assert messages land in Kafka via `kcat -C -t market-data-raw -c 5`

## Milestone 4 — Analytics Service (Metrics + Alerts)
- [ ] Implement `kafka_consumer.py` (consume `market-data-raw`, backpressure handling)
- [ ] Implement `metrics_calculator.py` (volatility, max drawdown, unrealized P&L; rolling window in Redis)
- [ ] Implement `alert_engine.py` (thresholds from config; emit alerts to Redis Pub/Sub and Postgres)
- [ ] Implement `database_writer.py` to persist raw events/metrics to TimescaleDB
- [ ] Wire service `main.py` loop with graceful shutdown and structured logging
- [ ] Tests: unit tests for metrics + alerts; integration `test_kafka_to_redis` and `test_alert_workflow`
- [ ] Verification: docker-compose bring up redpanda/redis/postgres + analytics; feed fixtures → observe metrics keys and alert rows

## Milestone 5 — API Service (FastAPI)
- [ ] Scaffold FastAPI app with routers: `metrics.py`, `alerts.py`, `replay.py`, `health.py`
- [ ] Add middleware: Firebase auth verifier, CORS, rate limiting (slowapi + Redis)
- [ ] Implement services: `redis_subscriber.py` (subscribe to alerts), `database_query.py` (Timescale queries), `sse_manager.py`
- [ ] Pydantic models for metrics/alerts/replay; error model from `docs/api_spec.md`
- [ ] Tests: unit tests for auth/models; integration `test_metrics_endpoint`, `test_replay_endpoint`, `test_sse_stream`
- [ ] Verification: `uvicorn services.api.main:app` locally; hit `/health`, `/api/metrics/latest`, `/api/alerts/stream` (with mocked auth)

## Milestone 6 — Frontend (React + Firebase)
- [ ] Bootstrap React app with Vite/CRA; set up Firebase auth wrapper
- [ ] Implement services: `api_client.ts`, `sse_client.ts`, `firebase_auth.ts`
- [ ] Components: `PriceChart`, `PortfolioSummary`, `MetricsDisplay`, `AlertLog`, `EventReplay`
- [ ] Hooks: `useMetricsStream`, `useAlerts`, `useReplay`
- [ ] Styling: global layout + responsive grid; basic theming
- [ ] Tests: component tests for chart + alert log; hook test for SSE client (mocked EventSource)
- [ ] Verification: `npm test` and manual run `npm start` -> confirm live metrics/alerts update

## Milestone 7 — End-to-End & Observability
- [ ] Write `tests/e2e/` to replay fixtures through ingestion → analytics → API → frontend (cypress/playwright for UI optional)
- [ ] Add logging/metrics dashboard: scrape container logs or add minimal Prometheus/Grafana note
- [ ] Add `docker-compose.test.yml` to orchestrate services + tests
- [ ] Tests: `docker-compose -f docker-compose.test.yml up --abort-on-container-exit`
- [ ] Verification: e2e passes; alerts visible in UI during replay

## Milestone 8 — CI/CD & Deployment
- [ ] Finalize `.github/workflows/test.yml` (lint, type check, unit/integration) and `deploy.yml` (build/push images → Render/Vercel)
- [ ] Add container hardening (non-root user, slim images) in each Dockerfile
- [ ] Add `docker-compose.prod.yml` or deployment docs for cloud free-tier (Upstash/Neon/Render/Vercel)
- [ ] Add uptime check (UptimeRobot hitting `/health`)
- [ ] Verification: CI green on PR; manual deploy run succeeds; health check passes

## Milestone 9 — Documentation & Security Pass
- [ ] Update `README.md` with run instructions, service overview, and troubleshooting
- [ ] Document configs in `config/` and sample env vars in `.env.example`
- [ ] Run security checklist from `docs/security_guidelines.md` (auth enforced, CORS restricted, rate limiting on)
- [ ] Add postmortem/learning notes to `docs/learning_notes.md`
- [ ] Verification: checklist items ticked; docs read cleanly

## Maintenance (ongoing)
- [ ] Weekly dependency audit (`pip list --outdated`, `npm audit`)
- [ ] Monitor Kafka/Redis usage vs free-tier limits (ingestion window respected)
- [ ] Add new alert rules/metrics as needed; keep tests in sync
