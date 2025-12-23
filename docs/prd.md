# Product Requirements Document (PRD)
## Product Overview

This project is a **real-time market monitoring platform** designed to help active investors understand market conditions during periods of high volatility.

The platform focuses on **market state awareness**, rather than trading execution. It provides real-time metrics, derived analytics, and event replay capabilities to support informed decision-making under uncertainty.

**Engineering Focus:** 
* Stream Processing: Implementing rolling window calculations (volatility, drawdowns) in real-time.
* Data Pipeline Architecture: Kafka-based ingestion, time-series aggregation, efficient storage (TimescaleDB).
* Cloud-Native DevOps: Demonstrating CI/CD maturity, containerized microservices, free-tier cost optimization.
* Code Quality: Comprehensive testing, type safety, error handling, production-ready standards.


## Target Users

Primary User
- Active investors or traders who monitor markets, Portfolio Greeks, Mark-to-Market (MtM) values, and exposure limits.
- Users who rely on alerts and metrics rather than automated trading systems.

### User Problems

Users face the following challenges:

- Market data updates continuously and rapidly.
- Raw price movements are noisy and difficult to interpret.
- Important market events may be missed during high volatility.
- Post-event analysis is often fragmented or unavailable.

### User Stories (MVP)
1. Real-Time Market Monitoring

    As an active investor,
    I want to monitor real-time market metrics (**price, volatility, portfolio Mark-to-Market (MtM), unrealized P&L**), so that I can understand current portfolio performance at a glance.
    As an active investor,
    I want to view rolling statistics over configurable time windows,so that I can distinguish normal market fluctuations from abnormal behavior. 

3. Alerting on Derived Metrics

    As an active investor,
    I want to receive alerts when derived market metrics exceed predefined thresholds, so that I can react during periods of high volatility. Example: if price of a stock dropped by 3% in a short period, I want to know.

4. Event Replay

    As an active investor,
    I want to replay historical market events around an alert (e.g 5 mins before and after the the alert), so that I can understand what led to the market movement.
    

## Functional Scope (MVP)



### A. Ingestion Layer
Real-time market data ingestion (simulated or adapter-based)
* **Data Source:** Binance WebSocket API (Real-time L1 Ticker) or high-fidelity simulated streams.
* **Sampling Frequency:** 500ms intervals.
* **Standardization:** An Ingestion Service maps various source formats into a unified JSON schema sent to the **Kafka Topic** (`market-data-raw`).
* Note: This layer is to replace traditional, static Excel-based tools. By using a Python/Kafka stream-processing architecture, I enabled real-time monitoring and automated alerting that simply isn't possible in a spreadsheet environment.



### B. Analytics Engine
Provide rolling statistical analysis and portfolio tracking.

* **Technology Stack:** Python for stream processing.
* **Core Metrics:**
    * **Rolling Volatility:** Standard deviation (σ) over rolling 30-second window.
    * **Max Drawdown (MDD):** Tracking the peak-to-trough decline.
    * **Portfolio Mark-to-Market (MtM):** Current position value based on real-time prices.
    * **Unrealized P&L:** Difference between entry value and current value.

* **Alert Rules:**
    * Price volatility exceeds threshold (e.g., >5%)
    * Drawdown exceeds threshold (e.g., >3%)
    * Unrealized loss exceeds threshold (e.g., <-5%)

* **Event Storage:** Persist all raw market events to TimescaleDB for replay capability.


### C. Visualization Dashboard

* **Authentication:** Firebase Auth (Google OAuth)
* **Widgets:**
    * **Real-Time Price Chart:** Live price updates with volatility overlay.
    * **Portfolio Summary:** Entry value, current value, unrealized P&L, percentage change.
    * **Metrics Display:** Current volatility (%), max drawdown (%), rolling statistics.
    * **Alert Log:** Real-time scrolling list of threshold breaches with timestamps.
    * **Event Replay:** Click alert → view 5-minute window (before/after) with annotated chart.



### Excluded (Future Work)
- Automated trading or order execution
- Advanced risk models (e.g., VaR, Greeks)
- Multi-portfolio aggregation
- Correlation heatmap / cross-asset analysis



## Evaluation / Success Criteria

The MVP is considered successful if:

- **Real-time Performance:** Dashboard updates within <500ms of new market data arrival.
- **Reliability:** Alerts trigger with >99% accuracy; no dropped events during ingestion window (8-9 AM UTC).
- **Usability:** Event replay accessible within 2 seconds; intuitive alert-to-root-cause flow.
- **Stability:** System handles 7,200 messages/day (1-hour ingestion window) without data loss or errors.
- **Code Quality:** 70%+ test coverage, CI/CD pipeline, clear documentation, production-ready error handling.

## Technical Constraints & Design Goals

To align with portfolio objectives, the implementation should emphasize:

- **Stream Processing:** Demonstrate mastery of rolling window calculations, time-series aggregation, real-time metric computation.
- **Backend Performance:** Async I/O, efficient state management (Redis), low-latency response times.
- **Data Engineering:** Multi-layer architecture (ingestion → processing → storage), time-series database optimization, data retention policies.
- **Cloud-Native Architecture:** Free-tier cost optimization (time-windowed ingestion), containerization, CI/CD maturity.
- **Code Quality:** Comprehensive testing (unit, integration, E2E), error handling, monitoring-ready design.
- **Maintainability:** Clear separation of concerns, easy to extend (add new metrics, alerts, symbols).