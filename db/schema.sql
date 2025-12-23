-- TimescaleDB schema for Market Watcher
-- Initializes hypertables for raw market events and supporting tables for alerts and positions.

CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- for gen_random_uuid

-- Raw market data (primary source for replay)
CREATE TABLE IF NOT EXISTS market_events (
    time        TIMESTAMPTZ NOT NULL,
    symbol      TEXT        NOT NULL,
    price       NUMERIC     NOT NULL,
    volume      NUMERIC     NOT NULL,
    source      TEXT        NOT NULL DEFAULT 'binance'
);

SELECT create_hypertable('market_events', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_market_events_symbol_time
    ON market_events (symbol, time DESC);

-- Derived metrics (latest snapshot per symbol)
CREATE TABLE IF NOT EXISTS metrics_latest (
    symbol           TEXT        PRIMARY KEY,
    volatility_pct   NUMERIC     NOT NULL,
    max_drawdown_pct NUMERIC     NOT NULL,
    unrealized_pnl   NUMERIC     NOT NULL,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Alerts history
CREATE TABLE IF NOT EXISTS alert_logs (
    alert_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol         TEXT         NOT NULL,
    metric         TEXT         NOT NULL,
    threshold      NUMERIC      NOT NULL,
    trigger_value  NUMERIC      NOT NULL,
    severity       TEXT         NOT NULL DEFAULT 'info',
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    details        JSONB        DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_alert_logs_symbol_created_at
    ON alert_logs (symbol, created_at DESC);

-- Optional: portfolio positions to compute MtM/Unrealized P&L
CREATE TABLE IF NOT EXISTS portfolio_positions (
    position_id   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol        TEXT         NOT NULL,
    quantity      NUMERIC      NOT NULL,
    entry_price   NUMERIC      NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Retention policy for raw events (7 days)
SELECT add_retention_policy('market_events', INTERVAL '7 days', if_not_exists => TRUE);
