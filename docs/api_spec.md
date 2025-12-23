# API Specification (MVP)

Base URL (local): `http://localhost:8000`
Authentication: Firebase ID token in `Authorization: Bearer <token>` (except `/health`).
Content Type: `application/json` unless noted. Streaming endpoints use `text/event-stream`.

---

## Health
- `GET /health`
  - **Auth:** none
  - **Response:** `{ "status": "ok" }`

---

## Metrics (Real-Time)
- `GET /api/metrics/stream`
  - **Description:** Server-Sent Events stream of derived metrics per symbol.
  - **Auth:** required
  - **Response event payload:**
    ```json
    {
      "symbol": "BTCUSDT",
      "volatility_pct": 2.15,
      "max_drawdown_pct": -1.8,
      "unrealized_pnl": 150.25,
      "timestamp": "2025-12-23T08:05:00Z"
    }
    ```

- `GET /api/metrics/latest?symbol=BTCUSDT`
  - **Description:** Latest metrics snapshot for a symbol.
  - **Auth:** required
  - **Response:** same schema as above (non-streaming).

---

## Alerts
- `GET /api/alerts`
  - **Query params:**
    - `symbol` (optional)
    - `limit` (optional, default 50)
  - **Auth:** required
  - **Response:**
    ```json
    [
      {
        "alert_id": "uuid",
        "symbol": "BTCUSDT",
        "metric": "volatility",
        "threshold": 5.0,
        "trigger_value": 5.2,
        "severity": "warning",
        "timestamp": "2025-12-23T08:05:10Z",
        "details": { "window_seconds": 30 }
      }
    ]
    ```

- `GET /api/alerts/stream`
  - **Description:** SSE stream for newly triggered alerts.
  - **Auth:** required
  - **Response event payload:** same as `GET /api/alerts` items.

---

## Replay
- `GET /api/replay?alert_id=<uuid>&window_seconds=300`
  - **Description:** Returns raw events ±window around alert timestamp.
  - **Auth:** required
  - **Response:**
    ```json
    {
      "alert_id": "uuid",
      "symbol": "BTCUSDT",
      "start": "2025-12-23T08:00:10Z",
      "end": "2025-12-23T08:10:10Z",
      "events": [
        {"time": "2025-12-23T08:05:00Z", "price": 50000.1, "volume": 1.5},
        {"time": "2025-12-23T08:05:01Z", "price": 49950.0, "volume": 1.2}
      ]
    }
    ```

---

## Raw Market Data (Optional for Debug)
- `GET /api/market-data?symbol=BTCUSDT&limit=200`
  - **Description:** Recent raw events from TimescaleDB.
  - **Auth:** required
  - **Response:** array of `{ time, symbol, price, volume, source }`

---

## Auth Helper (Optional)
- `POST /auth/verify`
  - **Description:** Verifies Firebase ID token; returns user info.
  - **Body:** `{ "token": "<id_token>" }`
  - **Response:** `{ "uid": "...", "email": "..." }`

---

## Error Model
- All errors follow:
  ```json
  { "error": "message", "details": "optional context" }
  ```

- Common status codes:
  - `400` invalid request
  - `401` unauthorized / invalid token
  - `404` not found
  - `429` rate limited
  - `500` server error

---

## Event Schemas (Kafka / SSE)

### `market-data-raw` (Kafka)
```json
{
  "timestamp": "ISO8601",
  "symbol": "BTCUSDT",
  "price": 50000.00,
  "volume": 1.5,
  "source": "binance"
}
```

### `metrics-calculated` (Kafka or Redis)
```json
{
  "timestamp": "ISO8601",
  "symbol": "BTCUSDT",
  "volatility_pct": 2.15,
  "max_drawdown_pct": -1.8,
  "unrealized_pnl": 150.25
}
```

### `alerts` (Kafka/Redis PubSub)
```json
{
  "alert_id": "uuid",
  "symbol": "BTCUSDT",
  "metric": "volatility",
  "threshold": 5.0,
  "trigger_value": 5.2,
  "severity": "warning",
  "timestamp": "ISO8601",
  "details": { "window_seconds": 30 }
}
```
