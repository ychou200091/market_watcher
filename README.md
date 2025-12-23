
# Market Watcher

Real-time market monitoring MVP: exchange ingestion → streaming analytics → alerts → FastAPI + React dashboard. Free-tier friendly, portfolio-ready.

## What it does (User Stories)
- Real-Time Market Monitoring: monitor real-time market metrics (**price, volatility, portfolio Mark-to-Market (MtM), unrealized P&L**) to understand current portfolio performance 
- view rolling statistics over configurable time windows,so that I can distinguish normal market fluctuations from abnormal behavior. 
- Alerting on when derived market metrics exceed predefined thresholds.
- Event Replay around an event alert.


## What it does (Dev side of the view)

**Data Pipeline:**
- Ingest live prices (Binance/simulator) via WebSocket → Kafka/Redpanda.
- Compute rolling volatility, max drawdown, MtM/unrealized PnL; hot state in Redis, history in TimescaleDB.
- Trigger alerts on thresholds; expose REST + SSE for dashboard.

**Frontend:**
- Dashboard shows live metrics, alerts, and replay (Firebase auth).

**Architecture:**
- Microservices architecture with shared utilities.

**Technical Highlights:**
- **Stream Processing:** Rolling window calculations (volatility, drawdowns) in real-time.
- **Data Pipeline:** Kafka-based ingestion, time-series aggregation, efficient storage (TimescaleDB).
- **Cloud-Native DevOps:** CI/CD maturity, containerized microservices, free-tier cost optimization.
- **Code Quality:** Comprehensive testing, type safety, error handling, production-ready standards.

## Architecture (per decisions)
- Services: ingestion (WS→Kafka), analytics (Kafka→metrics/alerts→Redis/DB), api (FastAPI/SSE), frontend (React).
- Infra local: Redpanda, Redis, TimescaleDB via docker-compose.
- Shared utilities under `services/shared` (Kafka/Redis/DB clients, logging, exceptions).

## License

Copyright 2025

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
