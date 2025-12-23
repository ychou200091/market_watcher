# Project Development Guidelines for AI Agents

**Purpose:** Ensure consistent, maintainable, testable, and production-ready code across all services. Be A senior software engineer.

---

## 1. Naming Conventions

### General Rules
- **Always use `snake_case`** for all Python identifiers:
  - Variables: `market_data`, `alert_threshold`, `connection_pool`
  - Functions: `calculate_volatility()`, `fetch_market_events()`, `trigger_alert()`
  - Files: `ingestion_service.py`, `metrics_calculator.py`, `database_connection.py`
  - Directories: `market_data/`, `alert_engine/`, `test_integration/`

- **Constants:** Use `SCREAMING_SNAKE_CASE`
  ```python
  MAX_RETRY_ATTEMPTS = 3
  DEFAULT_WINDOW_SIZE = 60
  KAFKA_TOPIC_RAW_DATA = "market-data-raw"
  ```

- **Classes:** Use `PascalCase` (exception to snake_case rule)
  ```python
  class MarketDataIngestion:
  class AlertRulesEngine:
  class TimescaleDBConnection:
  ```

### File Naming
- Python modules: `alert_manager.py`, `kafka_consumer.py`
- Configuration files: `docker-compose.yml`, `pytest.ini`, `alembic.ini`
- Environment files: `.env.local`, `.env.production`
- Test files: `test_metrics_calculator.py`, `test_alert_triggers.py`

### Project-Specific Conventions
- Database tables: `market_events`, `alert_logs`, `user_preferences`
- Kafka topics: `market-data-raw`, `alerts`, `metrics-calculated`
- Redis keys: `price_window:{symbol}`, `metrics:{symbol}`, `alert:{alert_id}`
- API endpoints: `/api/metrics`, `/api/replay`, `/api/alerts`
- Docker services: `ingestion`, `analytics`, `api`, `frontend`, `redpanda`, `postgres`

---

## 2. File & Directory Structure

### Principles
- **Separation of Concerns:** Each service is self-contained with its own dependencies
- **Modularity:** Services communicate via well-defined interfaces (Kafka topics, REST APIs)
- **Testability:** Tests live adjacent to source code or in dedicated test directories
- **Configuration:** Environment-specific configs are externalized (not hardcoded)
- **Documentation:** Critical decisions and architectural patterns are documented

### Standard Project Layout
Refer to the detailed structure in [decisions.md](../docs/decisions.md#file-directory-structure).

### Directory Organization Rules
1. **Service-Level Isolation:**
   - Each service (ingestion, analytics, api) has its own:
     - `requirements.txt` or `pyproject.toml`
     - `Dockerfile`
     - `tests/` directory
     - `README.md` with service-specific documentation

2. **Shared Code:**
   - Place truly shared utilities in `services/shared/` or `common/`
   - Examples: logging config, Kafka client wrapper, database connection pool
   - Import shared modules explicitly; avoid implicit dependencies

3. **Configuration Management:**
   - Store configs in `config/` at root level
   - Use `.env` files for secrets (never commit to Git)
   - Use YAML/JSON for non-sensitive configs (alert thresholds, window sizes)

4. **Frontend Separation:**
   - React app lives in `frontend/` with standard structure:
     - `src/components/`, `src/services/`, `src/hooks/`, `src/utils/`
   - No backend logic in frontend; communicate via API only

---

## 3. Code Organization & Clean Code Principles

### Module Structure
Every Python file should follow this structure:

```python
"""
Module: services/analytics/metrics_calculator.py

Purpose:
    Calculates rolling window metrics (volatility, max drawdown, unrealized P&L)
    from real-time market data. Consumes from Kafka topic 'market-data-raw'
    and publishes computed metrics to Redis for frontend consumption.

Dependencies:
    - pandas: Rolling window calculations
    - redis: Metric storage
    - numpy: Statistical functions

Author: [Your Name or Team]
Last Updated: 2025-12-23
"""

# Standard library imports
import logging
from typing import List, Dict, Optional
from datetime import datetime

# Third-party imports
import pandas as pd
import numpy as np
import redis

# Local imports
from services.shared.kafka_client import KafkaConsumerWrapper
from services.shared.redis_client import RedisConnectionPool

# Module-level constants
WINDOW_SIZE = 60  # 30 seconds at 500ms sampling
VOLATILITY_THRESHOLD = 5.0  # 5% volatility triggers alert

# Configure logging
logger = logging.getLogger(__name__)


class MetricsCalculator:
    """
    Calculates rolling metrics from market data streams.
    
    Attributes:
        window_size (int): Number of data points in rolling window
        redis_client (redis.Redis): Connection to Redis cache
    """
    
    def __init__(self, window_size: int = WINDOW_SIZE):
        """
        Initialize metrics calculator.
        
        Args:
            window_size: Rolling window size (default: 60 data points)
        """
        self.window_size = window_size
        self.redis_client = RedisConnectionPool.get_connection()
        logger.info(f"MetricsCalculator initialized with window_size={window_size}")
    
    def calculate_volatility(self, prices: List[float]) -> float:
        """
        Calculate rolling volatility (standard deviation) of price series.
        
        Formula: σ = sqrt(Σ(x - μ)² / N) where μ is mean, N is window size
        
        Args:
            prices: List of prices in rolling window (must have >= 2 elements)
        
        Returns:
            float: Volatility as percentage (e.g., 2.5 = 2.5% volatility)
        
        Raises:
            ValueError: If prices list has < 2 elements
        
        Example:
            >>> calc = MetricsCalculator()
            >>> prices = [100, 101, 99, 102, 98]
            >>> volatility = calc.calculate_volatility(prices)
            >>> print(f"Volatility: {volatility:.2f}%")
            Volatility: 1.47%
        """
        if len(prices) < 2:
            raise ValueError("Need at least 2 prices to calculate volatility")
        
        # Calculate standard deviation as percentage of mean
        mean_price = np.mean(prices)
        std_dev = np.std(prices)
        volatility_pct = (std_dev / mean_price) * 100
        
        logger.debug(f"Calculated volatility: {volatility_pct:.2f}% from {len(prices)} prices")
        return round(volatility_pct, 2)
```

### Clean Code Checklist
- ✅ **Single Responsibility:** Each function does ONE thing well
- ✅ **Descriptive Names:** Function/variable names reveal intent (`calculate_max_drawdown()`, not `calc()`)
- ✅ **Small Functions:** Aim for < 30 lines; extract complex logic into helpers
- ✅ **No Magic Numbers:** Use named constants (`MAX_RETRIES = 3`, not `for i in range(3)`)
- ✅ **Error Handling:** Catch specific exceptions; log errors with context
- ✅ **Type Hints:** Use Python 3.9+ type hints for all function signatures
- ✅ **Docstrings:** Every public function has Google-style docstring

### Anti-Patterns to Avoid
- ❌ God classes (classes that do too much)
- ❌ Long functions (>50 lines = refactor)
- ❌ Deep nesting (max 3 levels of indentation)
- ❌ Global state (use dependency injection)
- ❌ Hardcoded values (use config files or env vars)
- ❌ Commented-out code (use Git; delete dead code)

---

## 4. Documentation Requirements

### File-Level Documentation
Every source file MUST start with a module docstring:

```python
"""
Module: services/analytics/alert_engine.py

Purpose:
    Monitors real-time metrics (volatility, drawdown, P&L) and triggers alerts
    when thresholds are breached. Publishes alerts to Redis Pub/Sub for
    real-time delivery to frontend dashboard.

Core Functionality:
    - Load alert rules from config/alert_thresholds.yml
    - Subscribe to metrics updates from Redis
    - Evaluate rules against incoming metrics
    - Persist triggered alerts to PostgreSQL (alert_logs table)
    - Publish alert events to Redis channel 'alerts:realtime'

Dependencies:
    - Redis Pub/Sub for real-time messaging
    - PostgreSQL for alert persistence
    - PyYAML for config parsing

Configuration:
    - Alert thresholds: config/alert_thresholds.yml
    - Database connection: env var DB_CONNECTION_STRING
    - Redis connection: env var REDIS_URL

Example Config (alert_thresholds.yml):
    volatility:
      threshold: 5.0  # Trigger if >5%
      enabled: true
    drawdown:
      threshold: 3.0  # Trigger if >3%
      enabled: true

Author: Market Watcher Team
Last Updated: 2025-12-23
"""
```

### Function Documentation (Google-Style Docstrings)
```python
def fetch_market_events(
    symbol: str,
    start_time: datetime,
    end_time: datetime,
    limit: Optional[int] = None
) -> List[Dict[str, any]]:
    """
    Fetch historical market events from TimescaleDB within time range.
    
    Queries the 'market_events' hypertable for events matching the symbol
    and falling within [start_time, end_time]. Results are ordered by
    timestamp ascending.
    
    Args:
        symbol: Trading symbol (e.g., 'BTCUSDT', 'ETHUSDT')
        start_time: Start of time range (inclusive)
        end_time: End of time range (inclusive)
        limit: Maximum number of events to return (default: no limit)
    
    Returns:
        List of event dictionaries with schema:
        [
            {
                'time': datetime,
                'symbol': str,
                'price': Decimal,
                'volume': Decimal
            },
            ...
        ]
    
    Raises:
        DatabaseConnectionError: If database is unreachable
        ValueError: If start_time > end_time
    
    Example:
        >>> from datetime import datetime, timedelta
        >>> end = datetime.utcnow()
        >>> start = end - timedelta(minutes=5)
        >>> events = fetch_market_events('BTCUSDT', start, end, limit=100)
        >>> print(f"Retrieved {len(events)} events")
    
    Note:
        Uses parameterized query to prevent SQL injection. Query is optimized
        for TimescaleDB hypertable with time-based partitioning.
    """
    # Implementation...
```

### Inline Comments
Use comments to explain **WHY**, not **WHAT**:

```python
# ✅ Good: Explains rationale
# Use exponential backoff to avoid overwhelming Kafka during broker recovery
retry_delay = min(2 ** attempt, 60)

# ❌ Bad: Restates code
# Set retry delay to 2 to the power of attempt
retry_delay = 2 ** attempt
```

### Complex Algorithm Documentation
For non-trivial logic, add explanatory comments:

```python
def calculate_max_drawdown(prices: List[float]) -> float:
    """
    Calculate maximum drawdown (MDD) in percentage terms.
    
    Algorithm:
        1. Track running maximum price (peak)
        2. For each price, calculate drawdown from peak: (price - peak) / peak
        3. Track the minimum (most negative) drawdown seen
    
    Example:
        Prices: [100, 120, 90, 110]
        Drawdowns: [0%, 0%, -25%, -8.33%]
        MDD: -25%
    """
    peak = prices[0]
    max_dd = 0.0
    
    for price in prices:
        # Update peak if current price exceeds it
        if price > peak:
            peak = price
        
        # Calculate current drawdown from peak
        drawdown = (price - peak) / peak
        
        # Track most severe drawdown (most negative value)
        if drawdown < max_dd:
            max_dd = drawdown
    
    return round(max_dd * 100, 2)  # Convert to percentage
```

---

## 5. Testing Requirements

### Test Organization
- **Unit Tests:** Test individual functions in isolation
  - Location: `services/<service_name>/tests/unit/`
  - File naming: `test_<module_name>.py`
  - Example: `services/analytics/tests/unit/test_metrics_calculator.py`

- **Integration Tests:** Test service-to-service interactions
  - Location: `services/<service_name>/tests/integration/`
  - Example: Kafka producer → consumer flow

- **End-to-End Tests:** Test full user flows
  - Location: `tests/e2e/`
  - Example: Market data ingestion → analytics → alert → frontend

### Writing Testable Code
Every function should be designed for testability:

```python
# ❌ Hard to test: Direct database access
def get_recent_alerts():
    db = psycopg2.connect("postgresql://...")
    cursor = db.cursor()
    cursor.execute("SELECT * FROM alerts ORDER BY time DESC LIMIT 10")
    return cursor.fetchall()

# ✅ Easy to test: Dependency injection
def get_recent_alerts(db_connection: DatabaseConnection, limit: int = 10) -> List[Alert]:
    """Fetch most recent alerts from database."""
    query = "SELECT * FROM alerts ORDER BY time DESC LIMIT %s"
    return db_connection.execute(query, (limit,))

# Test with mock:
def test_get_recent_alerts():
    mock_db = MockDatabaseConnection()
    mock_db.set_result([Alert(...), Alert(...)])
    alerts = get_recent_alerts(mock_db, limit=2)
    assert len(alerts) == 2
```

### Test Structure (AAA Pattern)
```python
def test_calculate_volatility_with_valid_prices():
    """Test volatility calculation returns expected percentage."""
    # Arrange: Set up test data
    calculator = MetricsCalculator(window_size=5)
    prices = [100.0, 101.0, 99.0, 102.0, 98.0]
    expected_volatility = 1.47  # Pre-calculated
    
    # Act: Execute function
    actual_volatility = calculator.calculate_volatility(prices)
    
    # Assert: Verify results
    assert abs(actual_volatility - expected_volatility) < 0.01, \
        f"Expected {expected_volatility}%, got {actual_volatility}%"
```

### Test Coverage Requirements
- **Minimum:** 70% code coverage across all services
- **Critical paths:** 90%+ coverage for:
  - Metrics calculations
  - Alert triggering logic
  - Database queries (replay, alert storage)
  - Kafka message processing

### Pytest Configuration
Use fixtures for common setup:

```python
# conftest.py
import pytest
from services.shared.redis_client import RedisClient

@pytest.fixture
def redis_client():
    """Provide Redis client for tests (uses test database)."""
    client = RedisClient(db=15)  # Use dedicated test DB
    yield client
    client.flushdb()  # Clean up after test

@pytest.fixture
def sample_market_data():
    """Provide sample market data for testing."""
    return [
        {"time": "2025-12-23T08:00:00Z", "symbol": "BTCUSDT", "price": 50000, "volume": 1.5},
        {"time": "2025-12-23T08:00:01Z", "symbol": "BTCUSDT", "price": 50050, "volume": 2.0},
    ]
```

---

## 6. Error Handling & Logging

### Exception Handling
- **Catch specific exceptions:** Never use bare `except:`
  ```python
  # ✅ Good
  try:
      result = risky_operation()
  except ConnectionError as e:
      logger.error(f"Database connection failed: {e}")
      raise DatabaseConnectionError("Unable to reach database") from e
  except ValueError as e:
      logger.warning(f"Invalid input: {e}")
      return None
  
  # ❌ Bad
  try:
      result = risky_operation()
  except:
      pass  # Silent failure; impossible to debug
  ```

- **Log errors with context:**
  ```python
  try:
      process_market_event(event)
  except Exception as e:
      logger.error(
          f"Failed to process event for {event['symbol']} at {event['time']}: {e}",
          extra={"symbol": event["symbol"], "event_id": event["id"]}
      )
      raise
  ```

### Logging Standards
- **Use structured logging:**
  ```python
  import logging
  
  logger = logging.getLogger(__name__)
  
  # Log levels:
  logger.debug("Detailed info for debugging")
  logger.info("Normal operation events")
  logger.warning("Unexpected but recoverable")
  logger.error("Error that needs attention")
  logger.critical("System-critical failure")
  ```

- **Never log sensitive data:**
  ```python
  # ❌ Bad: Logs password
  logger.info(f"Connecting to DB with password: {password}")
  
  # ✅ Good: Omits sensitive data
  logger.info(f"Connecting to DB at {db_host}:{db_port}")
  ```

- **Include correlation IDs:**
  ```python
  # Add request_id for tracing across services
  logger.info(
      f"Processing alert {alert_id}",
      extra={"request_id": request_id, "alert_id": alert_id}
  )
  ```

---

## 7. Configuration Management

### Environment Variables
- **All secrets in env vars:** Never hardcode in source
  ```python
  import os
  
  DB_PASSWORD = os.getenv("DB_PASSWORD")
  if not DB_PASSWORD:
      raise EnvironmentError("DB_PASSWORD environment variable not set")
  ```

- **Provide defaults for non-secrets:**
  ```python
  KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
  REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
  LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
  ```

### Configuration Files
Use YAML for complex configs:

```yaml
# config/alert_thresholds.yml
alerts:
  volatility:
    enabled: true
    threshold: 5.0
    window_seconds: 30
  
  drawdown:
    enabled: true
    threshold: 3.0
  
  unrealized_pnl:
    enabled: true
    threshold: -5.0  # Negative = loss
```

Load with validation:
```python
import yaml
from typing import Dict

def load_alert_config(path: str = "config/alert_thresholds.yml") -> Dict:
    """Load and validate alert configuration."""
    with open(path, 'r') as f:
        config = yaml.safe_load(f)
    
    # Validate required keys
    required_keys = ["volatility", "drawdown", "unrealized_pnl"]
    for key in required_keys:
        if key not in config["alerts"]:
            raise ValueError(f"Missing required config key: alerts.{key}")
    
    return config
```

---

## 8. Code Quality Tools

### Pre-Commit Checks
Run these before every commit:

```bash
# Format code (Black + isort)
black services/ --line-length 100
isort services/ --profile black

# Lint (Flake8)
flake8 services/ --max-line-length 100 --ignore E203,W503

# Type check (mypy)
mypy services/ --strict

# Run tests
pytest services/ --cov=services --cov-report=term-missing
```

### CI/CD Integration
GitHub Actions should enforce:
- All tests pass
- Code coverage ≥ 70%
- No linting errors
- Type checking passes
- No security vulnerabilities (bandit, safety)

---

## 9. Git & Version Control

### Commit Messages
Follow conventional commits:

```
feat(analytics): add max drawdown calculation
fix(ingestion): handle WebSocket reconnection
docs(readme): update installation instructions
test(metrics): add unit tests for volatility calc
refactor(api): extract auth logic to middleware
```

### Branch Strategy
- `main`: Production-ready code
- `develop`: Integration branch for features
- `feature/<name>`: Individual features
- `fix/<name>`: Bug fixes

### Pull Request Requirements
- Description of changes
- Tests added/updated
- Documentation updated
- No merge conflicts
- Approved by at least one reviewer (for teams)

---

## 10. Service-Specific Guidelines

### Ingestion Service
- **Graceful shutdown:** Close WebSocket, flush Kafka buffer
- **Reconnection logic:** Exponential backoff for retries
- **Message validation:** Validate schema before publishing to Kafka

### Analytics Service
- **Stateless design:** No local state; use Redis for persistence
- **Idempotency:** Re-processing same event should produce same result
- **Performance:** Process messages within 100ms (target)

### API Service
- **Input validation:** Use Pydantic models for all endpoints
- **Rate limiting:** Enforce per-user limits
- **CORS:** Whitelist frontend origin only

### Frontend
- **Component structure:** One component per file
- **State management:** Use React Context or Zustand
- **Error boundaries:** Catch React errors gracefully
- **Accessibility:** Use semantic HTML, ARIA labels

---

## 11. Docker & Deployment

### Dockerfile Best Practices
```dockerfile
# Use specific versions (not 'latest')
FROM python:3.11-slim

# Run as non-root user
RUN adduser --disabled-password --gecos '' appuser
USER appuser

# Copy only requirements first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY . .

# Expose port (documentation only)
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:8000/health || exit 1

# Run application
CMD ["python", "main.py"]
```

### Docker Compose
- Pin image versions
- Use health checks for dependencies
- Mount volumes for development (not production)
- Expose only necessary ports

---

## 12. Performance Optimization

### Python-Specific
- Use async/await for I/O-bound operations
- Batch database queries (avoid N+1 problem)
- Cache expensive calculations in Redis
- Use connection pooling (DB, Redis, Kafka)
- Profile with `cProfile` before optimizing

### Database
- Add indexes on frequently queried columns (symbol, time)
- Use TimescaleDB compression for old data
- Set appropriate retention policies

### Kafka
- Batch messages when publishing
- Use appropriate consumer group IDs
- Monitor consumer lag

---

## 13. Security Reminders

Refer to [security_guidelines.md](../docs/security_guidelines.md) for full details. Quick checklist:

- [ ] No secrets in code (use env vars)
- [ ] Input validation on all user inputs
- [ ] Parameterized SQL queries (no f-strings)
- [ ] HTTPS only in production
- [ ] Rate limiting on API endpoints
- [ ] CORS restricted to known origins
- [ ] Dependencies scanned for vulnerabilities

---

## 14. When in Doubt

If you encounter ambiguity:
1. **Check existing code:** Follow established patterns in the codebase
2. **Favor simplicity:** The simplest solution that works is usually best
3. **Ask for clarification:** Document assumptions if unsure
4. **Test extensively:** When uncertain, write more tests
5. **Document decisions:** Update docs/ with architectural choices

---

## Resources

- [PEP 8](https://peps.python.org/pep-0008/) — Python style guide
- [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html) — Docstring format
- [Clean Code by Robert Martin](https://www.oreilly.com/library/view/clean-code-a/9780136083238/) — Principles
- [12-Factor App](https://12factor.net/) — Cloud-native best practices
- [Effective Python](https://effectivepython.com/) — Python-specific patterns

---

**Remember:** Code is read far more often than it is written. Optimize for clarity and maintainability over cleverness.
