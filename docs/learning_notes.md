# Learning Notes — Market Watcher (給完全新手的解說)
這裡大部分先用AI assistance 來寫，而我會在製作時，時不時修改並加入我學到的東西。

這份筆記是專門寫給「剛開始做全端開發」的你。用簡單例子和比喻，帶你理解我們今天做了什麼、為什麼這樣設計、接下來怎麼一步步把這個專案做出來。英文專有名詞會保留，這樣你之後查資料更容易。

---

## 1. 我們在做什麼？（Big Picture）

想像你在看股票或加密貨幣的即時價格。價格一直在變，如果只看原始數字，很容易混亂、也不容易看出「是否有異常」。

這個專案叫「Market Watcher」，它是一個「即時監控平台」。它做三件事：
- 從資料來源（例如 Binance WebSocket）接收「即時價格」（Ingestion）。
- 即時計算有用的指標（Analytics），像是：
  - Rolling Volatility（滾動波動率）：最近一段時間的價格變動有多劇烈。
  - Max Drawdown（最大回撤）：價格從高點跌到低點最多跌了多少％。
  - MtM（Mark-to-Market）與 Unrealized P&L（未實現損益）。
- 把結果與警報（Alert）送到後端 API 與前端 Dashboard，並能回放事件（Replay）。

你可以把它想成：「Data ingestion 資料郵差系統」+「即時計算器」+「可視化儀表板」。

---

## 2. 資料怎麼流動？（Data Flow，用生活比喻）

- Binance WebSocket 就像「電台」不停播報價格。
- Ingestion Service（Python）像「翻譯+郵差」，把不同格式的資料翻成統一的 JSON，投遞到訊息管道 Kafka（本地用 Redpanda）。
- Analytics Engine（Python）像「數學小老師」，不停從 Kafka 拿資料，算出 Volatility、Max Drawdown 等，再把結果暫存到 Redis（快速記憶體），需要回放時存到 TimescaleDB（資料圖書館）。
- FastAPI（Python）是「服務台」，提供 API 與 SSE（Server-Sent Events）讓前端拿到即時資料。
- React 前端是「儀表板」，畫出圖表、顯示警報、支援事件回放。登入用 Firebase Auth（Google OAuth）。

---

## 3. 我們選了哪些工具？為什麼？（Why These Choices）

- Kafka（本地用 Redpanda）：像「高速道路」，每個主題（Topic）是一條車道，訊息車子（Message）在上面跑。
  - 為什麼不用 RabbitMQ？Kafka天生擅長「事件串流」與「重放歷史」，很適合即時資料與回放。
- Redis：像「超快記憶盒」，用來存最近 N 筆價格與計算結果（Rolling Window）。
  - 為什麼不用 Postgres 存這些？Redis在記憶體內，速度快，適合短期快取；Postgres在磁碟，適合長期保存與查詢。
- TimescaleDB（PostgreSQL 擴展）：像「時間序列圖書館」，專門存一大堆按時間排序的事件，查「某時段」很有效率。
  - 為什麼不用 InfluxDB？TimescaleDB 建在 Postgres 上，SQL 能力強、好用、且我們也需要 Postgres 存警報。
- FastAPI：Python 的現代化後端框架，速度快、支援 Async I/O、內建 OpenAPI 文件。
- SSE（Server-Sent Events）：比 WebSocket 更簡單的「單向即時推播」，很適合從後端推資料到前端。
  - 為什麼不用 WebSocket？SSE 足夠、部署簡單，MVP 不需要雙向通訊。
- React + Recharts：畫圖、顯示資料很方便，社群資源多、部署容易。
- Firebase Auth（Google OAuth）：免自建登入系統，安全且免費層足夠。

---

## 4. 檔案與資料夾如何安排？（Maintainable Structure）

我們把程式碼分成「服務（services）」：
- `services/ingestion`：負責接收市場資料、標準化、送到 Kafka。
- `services/analytics`：負責從 Kafka 消費、做計算、丟到 Redis/TimescaleDB 與觸發警報。
- `services/api`：負責提供 API 與 SSE、驗證使用者（Firebase Token）。
- `services/shared`：共用的連線工具、例外、記錄設定等。
- `frontend`：React 儀表板。

詳細結構在：[docs/decisions.md](docs/decisions.md#file-directory-structure) 與更新後的 [docs/project_scaffolding.md](docs/project_scaffolding.md)。

---

## 5. 我們今天準備了什麼？（Today’s Prep Work）

- 範本環境變數：[.env.example](.env.example)
- 本地容器編排（Docker Compose）：[docker-compose.yml](docker-compose.yml)
- 資料庫 Schema（TimescaleDB）：[db/schema.sql](db/schema.sql)
- API 規格文件（MVP）：[docs/api_spec.md](docs/api_spec.md)
- 快速指南 README： [README.md](README.md)
- 測試資料夾的固定測試檔：
  - [tests/fixtures/sample_market_data.json](tests/fixtures/sample_market_data.json)
  - [tests/fixtures/sample_alerts.json](tests/fixtures/sample_alerts.json)
- 初始 Python 相依套件清單： [requirements.txt](requirements.txt)
- 開發規範（給 AI/工程師）： [rules/agents.md](rules/agents.md)
- 專案腳手架（Scaffolding）文件更新： [docs/project_scaffolding.md](docs/project_scaffolding.md)
- 安全指南（簡明版）： [docs/security_guidelines.md](docs/security_guidelines.md)

這些準備讓你「不用還沒寫後端或前端」也能先把環境跑起來，確保路線清楚。

---

## 6. 指標是什麼？為什麼需要？（Metrics Explained）

- Rolling Volatility（滾動波動率）：看最近一小段時間（例如 30 秒）的價格「變動幅度」。
  - 直覺比喻：最近 30 秒的價格如果像過山車，Volatility 就高。
  - 簡單公式：$\sigma = \text{std\_dev}(\text{prices}) / \text{mean}(\text{prices}) \times 100\%$
- Max Drawdown（最大回撤）：最高點到最低點跌了幾％。
  - 直覺比喻：爬到山頂後一路下滑，滑到谷底的最大跌幅。
- MtM、Unrealized P&L：用「當前價格」計算你的持倉目前賺/賠多少（但還未賣出）。

為什麼需要？這些是讓「原始價格」變得「有意義」的視覺化訊號，協助你在高波動時理解市場狀態、快速反應。

---

## 7. 常見問題（Q&A）

**Q：為什麼 Kafka/Redpanda，而不是直接把資料丟進資料庫？**  
A：Kafka 是「即時事件流」的專家。它讓多個服務彼此解耦（decouple），並且能承受高吞吐。另外它支援重放（replay），很適合我們在某時段回看資料的需求。

**Q：為什麼 Redis？**  
A：Redis 在記憶體中，非常快。滾動計算需要快速拿「最近 N 筆資料」，Redis 完全適合；而且它也能做 Pub/Sub 推播警報。

**Q：TimescaleDB 有什麼好？**  
A：它是 Postgres 的時間序列擴充。你得到 Postgres 的穩定性與生態，外加時間序列查詢的加速（hypertable 與 retention policy）。

**Q：SSE 跟 WebSocket 有什麼差？**  
A：SSE 是單向（Server → Client），WebSocket 是雙向。MVP 我們只需要後端推資料給前端，SSE 較簡單、部署更省心。

**Q：Firebase Auth 為什麼好？**  
A：不用自己做登入系統與安全機制。Google OAuth 很常見，免費層夠用，且有完整 SDK。

**Q：這樣的架構會不會太複雜？**  
A：我們有分「本地（local）」和「雲端（cloud）」兩種路線：本地用 Docker Compose 跑 Redpanda/Redis/TimescaleDB；雲端用 Upstash/Render/Vercel。在 MVP 階段，我們已把複雜度壓低到合理範圍。

---

## 8. 安全（Security，簡單但重要）

- 秘密（secrets）放 `.env`，不要寫在程式碼裡。
- 只開放前端網域的 CORS（Cross-Origin Resource Sharing）。
- API 都要驗證（Firebase Token）。
- 使用參數化 SQL，避免 SQL Injection。
- 記錄（logging）不要寫出密碼或 token。

詳細清單在：[docs/security_guidelines.md](docs/security_guidelines.md)。

---

## 9. 我該如何開始？（Step-by-Step 開發流程）

### Step 0：準備工具
- 安裝：Python 3.11、Node 18、Docker、Git。
- 安裝 Python 開發工具：`black`、`flake8`、`mypy`、`pytest`（已在 [requirements.txt](requirements.txt)）。

### Step 1：設定環境變數
- 複製 `.env.example` → `.env`，填上 Firebase 與本地連線資訊。

### Step 2：跑本地服務
- 在專案根目錄執行：
```bash
docker-compose up --build
```
- 檢查 API 健康：打開 `http://localhost:8000/health`
- 打開前端：`http://localhost:3000`

### Step 3：實作 Ingestion Service（services/ingestion）
- 撰寫 `websocket_client.py` 連線 Binance（或 simulator），每 ~500ms 收到一筆資料。
- 用 `data_normalizer.py` 把資料轉成統一 JSON。
- 用 `kafka_publisher.py` 發佈到 `market-data-raw` Topic。
- 寫單元測試（tests/unit）。

### Step 4：實作 Analytics Engine（services/analytics）
- `kafka_consumer.py` 讀取 `market-data-raw`。
- `metrics_calculator.py` 計算 Volatility、Max Drawdown、MtM、P&L。
- `redis_state_manager.py` 存最近 N 筆；`database_writer.py` 寫入 TimescaleDB。
- `alert_engine.py` 根據閾值觸發警報，寫到 `alert_logs`，並用 Redis Pub/Sub 推播。
- 寫單元/整合測試。

### Step 5：實作 API（services/api）
- `routes/metrics.py` 提供 SSE（`/api/metrics/stream`）與快照（`/api/metrics/latest`）。
- `routes/alerts.py` 列出與推播警報（`/api/alerts`, `/api/alerts/stream`）。
- `routes/replay.py` 查 TimescaleDB 回放（`/api/replay?alert_id=...`）。
- `middleware/auth.py` 驗證 Firebase Token；`rate_limit.py` 做簡單限流。
- 參考規格：[docs/api_spec.md](docs/api_spec.md)。

### Step 6：前端（frontend）
- 用 React + Recharts 畫圖：PriceChart、MetricsDisplay、AlertLog、EventReplay。
- `services/sse_client.ts` 連 SSE；`services/api_client.ts` 呼叫 API。
- `AuthProvider.tsx` 包 Firebase Auth。

### Step 7：測試與品質
- 單元測試（pytest）：重點覆蓋 metrics、alert、replay。
- E2E 測試（tests/e2e）：從 ingestion → analytics → API → frontend。
- Lint/format/type-check：`black`、`flake8`、`mypy`。

### Step 8：CI/CD（GitHub Actions）
- 加入 `.github/workflows/test.yml`、`deploy.yml`。
- Build Docker image → 推 GHCR → 部署到 Render/Vercel。

### Step 9：雲端部署（Free Tier）
- Upstash Kafka（每天 10K 訊息限制）：只在 8–9 AM UTC 收資料。
- Upstash Redis、Neon Postgres（TimescaleDB 相容）、Render（FastAPI）、Vercel（React）。

---

## 10. 快速試跑與除錯（Debug Tips）

- TimescaleDB 已自動套用 [db/schema.sql](db/schema.sql)。如果 API 報錯，先確認資料庫有起來。
- Kafka（Redpanda）起不來時，重開 `docker-compose` 或減少記憶體占用。
- 無法登入？檢查 Firebase `.env` 是否填好 `FIREBASE_PRIVATE_KEY` 等欄位。

---

## 11. 小字典（Glossary）

- **WebSocket**：雙向即時連線；我們用它從 Binance 拿資料。
- **SSE（Server-Sent Events）**：後端推資料到前端的單向即時通道。
- **Kafka/Redpanda**：事件串流系統，Topic 是分類、Message 是事件。
- **Redis**：記憶體型資料庫，適合快取和 Pub/Sub。
- **TimescaleDB**：PostgreSQL 的時間序列擴展，適合查某時段資料。
- **FastAPI**：Python 的後端框架，速度快、型別安全、內建文件。
- **Firebase Auth**：Google 的身份驗證服務，簡化登入與安全問題。
- **Volatility**：波動率，越高代表變動越劇烈。
- **Max Drawdown**：最大回撤，最高點到最低點的最大跌幅（％）。
- **MtM/P&L**：以當前價格評估持倉價值與損益（未賣出稱為未實現損益）。

---

## 12. 結語：為什麼這樣設計「更好」？

- **模組化（Modular）**：每個服務只做一件事，維護容易、擴充方便。
- **可回放（Replay）**：用 Kafka + TimescaleDB 能在指定時段重看事件。
- **免費層友善（Free Tier Friendly）**：把即時收數據限制在 8–9 AM UTC，成本趨近 0。
- **工程品質（Quality）**：使用 FastAPI、Pydantic、pytest、黑白名單（CORS）、SSE、CI/CD，符合實務標準。
- **學習曲線（Learning）**：中文解說 + 英文關鍵字，方便你搜資料、查官方文件。

讀完這份筆記，你應該能掌握：我們的架構、工具選擇的理由、檔案如何組織、今天準備了什麼，與接下來怎麼一步步把它做出來。加油！你已經在正確的路上。
