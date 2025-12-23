# Project Scaffolding

This document defines a production-ready directory layout for the Market Watcher MVP. It matches the current PRD and decisions: Python stream processing, Kafka/Redpanda, TimescaleDB, Redis, FastAPI, and a React + Firebase-authenticated dashboard.


## Directory Structure

```text
market_watcher/
├── docs/                          # Product, decisions, context, security
│   ├── prd.md
│   ├── decisions.md
│   ├── context.md
│   ├── security_guidelines.md
│   └── project_scaffolding.md
│
├── rules/                         # Development guidelines
│   └── agents.md
│
├── config/                        # Non-secret configuration
│   ├── alert_thresholds.yml
│   ├── ingestion_schedule.yml
│   └── logging_config.yml
│
├── services/                      # Backend services
│   ├── shared/                    # Reusable utilities
│   │   ├── __init__.py
│   │   ├── kafka_client.py
│   │   ├── redis_client.py
│   │   ├── database_connection.py
│   │   ├── logging_setup.py
│   │   └── exceptions.py
│   │
│   ├── ingestion/                 # Binance/simulator → Kafka
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   ├── README.md
│   │   ├── main.py
│   │   ├── websocket_client.py
│   │   ├── data_normalizer.py
│   │   ├── kafka_publisher.py
│   │   ├── scheduler.py
│   │   └── tests/
│   │       ├── unit/
│   │       └── integration/
│   │
│   ├── analytics/                 # Metrics + alerts
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   ├── README.md
│   │   ├── main.py
│   │   ├── kafka_consumer.py
│   │   ├── metrics_calculator.py
│   │   ├── alert_engine.py
│   │   ├── redis_state_manager.py
│   │   ├── database_writer.py
│   │   └── tests/
│   │       ├── unit/
│   │       └── integration/
│   │
│   └── api/                       # FastAPI + SSE
│       ├── Dockerfile
│       ├── requirements.txt
│       ├── README.md
│       ├── main.py
│       ├── routes/
│       ├── middleware/
│       ├── models/
│       ├── services/
│       └── tests/
│           ├── unit/
│           └── integration/
│
├── frontend/                      # React dashboard
│   ├── Dockerfile
│   ├── package.json
│   ├── public/
│   └── src/
│       ├── components/
│       ├── services/
│       ├── hooks/
│       ├── utils/
│       └── styles/
│
├── tests/                         # Cross-service tests
│   └── e2e/
│
├── scripts/                       # Tooling helpers
│   ├── setup_local_env.sh
│   ├── seed_test_data.py
│   ├── run_tests.sh
│   └── deploy_cloud.sh
│
├── db/                            # SQL schema and seeds
│   └── schema.sql
│
├── .github/workflows/             # CI/CD pipelines
│   ├── test.yml
│   ├── deploy.yml
│   └── security_scan.yml
│
├── docker-compose.yml             # Local orchestration
├── docker-compose.test.yml        # Test orchestration
├── .env.example                   # Environment variable template
├── requirements.txt               # Root Python tooling deps
├── README.md                      # Quickstart + docs links
└── LICENSE                        # License file
```

## Folder & File Purpose (Delta from decisions)

- `services/shared`: Cross-service adapters (Kafka, Redis, Timescale), logging, exceptions.
- `services/ingestion`: WebSocket client(s), message normalization, Kafka producer, schedule to enforce 8–9 AM UTC window.
- `services/analytics`: Kafka consumer, rolling metrics, alert engine, Redis state, TimescaleDB writer.
- `services/api`: FastAPI app, Pydantic models, middleware (auth/rate-limit/CORS), SSE streaming, DB queries, Redis Pub/Sub subscriber.
- `frontend`: React UI (metrics, alerts, replay) with Firebase Auth wrapper.
- `config`: Non-secret YAML configs (alert thresholds, schedules, logging). Secrets live in `.env` only.
- `db/schema.sql`: TimescaleDB schema for market events, alerts, and retention policies.
- `tests/e2e`: Full-pipeline validation (ingestion → analytics → API → frontend).
- `.github/workflows`: CI (lint/type/test) and deploy jobs to GHCR/Render/Vercel.

## Notes on Tech Stack Alignment

- Stream processing uses Kafka/Redpanda locally; Upstash Kafka in cloud.
- TimescaleDB stores raw events and supports replay; Redis holds rolling state.
- FastAPI exposes metrics/alerts/replay via REST + SSE; Firebase provides auth.
- Docker Compose ensures local parity; GitHub Actions enforces tests and image builds.
