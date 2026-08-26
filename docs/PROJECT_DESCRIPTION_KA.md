# პროექტის დეტალური აღწერა და ჩამატებები

დიპლომი: **Real-Time CDC + Lakehouse Pipeline**  
(AdventureWorks → Star Schema → BI / ML)

---

## 1. რა დაემატა (ჩამატებები)

ქვემოთ არის ის, რაც **საბაზისო CDC/Flink/Iceberg სტეკს** დაემატა (ლექტორის მოთხოვნა + დაცვისთვის პრაქტიკული ნაწილი).

### 1.1. Airflow (batch orchestration)

| | |
|--|--|
| **რა არის** | Apache Airflow 2.8 — batch job-ების ორკესტრატორი |
| **რატომ დაემატა** | ლექტორის მოთხოვნა; streaming-ისგან გამიჯნული batch ფენა |
| **რას აკეთებს** | არ აანალიზებს მონაცემს — **გეგმავს/უშვებს** Python სკრიპტს |
| **DAG** | `lakehouse_customer_kmeans` |
| **გაშვება** | ხელით Trigger (`schedule=None`) ან ტერმინალი |
| **UI** | http://localhost:8085 (`admin` / `admin`) |
| **ფაილი** | `airflow/dags/lakehouse_kmeans_dag.py` |

### 1.2. Python ანალიზი MinIO-ზე

| | |
|--|--|
| **რა არის** | `analytics/kmeans_customers.py` |
| **რატომ დაემატა** | Lakehouse Gold-ზე ML ანალიზის დემონსტრაცია |
| **ტექნოლოგიები** | pandas, scikit-learn, boto3 (S3/MinIO) |
| **შემავალი** | MinIO → `iceberg_data/gold/fact_sales_order_line/data/*.parquet` |
| **გამომავალი** | MinIO → `analytics/customer_clusters/` (Parquet + CSV) |

### 1.3. K-Means კლასტერიზაცია

| | |
|--|--|
| **რა არის** | არასუპერვიზირებული ML — კლიენტების დაჯგუფება |
| **K** | 3 სეგმენტი |
| **ფიჩერები** | `order_lines`, `total_revenue`, `avg_line_value`, `unique_products` |
| **რისთვის** | კლიენტების სეგმენტაცია შეძენის ქცევით (მაგ. მცირე / საშუალო / VIP) |
| **სად ვნახო შედეგი** | MinIO Console → `lakehouse-admin/analytics/customer_clusters/` |

### 1.4. Metabase (BI დეშბორდი)

| | |
|--|--|
| **რა არის** | ვიზუალური BI Presto → Iceberg Gold-ზე |
| **რატომ დაემატა** | დაცვისთვის ვიზუალური შედეგი (არა მხოლოდ CLI SQL) |
| **UI** | http://localhost:3000 |
| **ლოგინი** | `admin@adventureworks.local` / `Admin123!` |
| **დეშბორდი** | AdventureWorks Sales (KPI, Revenue by Day, Top Products, Territory, Recent Orders) |
| **ფაილები** | `docs/BI_DASHBOARD_KA.md`, `scripts/configure-metabase.ps1` |

### 1.5. ექსპერიმენტი — CDC Latency + KPI ანგარიში

| | |
|--|--|
| **რა არის** | გაზომვადი დემო: INSERT → რამდენ წამში ჩანს Gold-ში |
| **სკრიპტი** | `scripts/run-experiment.ps1` |
| **იგივე ცვლილება** | რაც `demo-pipeline.ps1`-ში (ახალი შეკვეთა Postgres-ში) |
| **გაზომილი latency** | ≈ **9–14 წამი** (ბოლო გაშვება: **13.6 s**) |
| **ანგარიში** | `docs/experiment-results/latest.md` |
| **დოკი** | `docs/EXPERIMENT_KA.md` |

### 1.6. დოკუმენტაცია და სქემები

| ფაილი | შინაარსი |
|-------|----------|
| `docs/ARCHITECTURE_KA.md` | კომპონენტების დასაბუთება (Zookeeper, MinIO, Airflow, K-Means, Metabase) |
| `docs/FULL_SCHEMA_KA.md` | მაქსიმალურად დეტალური Mermaid სქემები |
| `docs/DIAGRAMS_COPY_PASTE.md` | დიაგრამების კოდი mermaid.live-სთვის |
| `docs/BI_DASHBOARD_KA.md` | Metabase setup |
| `docs/EXPERIMENT_KA.md` | ექსპერიმენტის აღწერა |
| `docs/PROJECT_DESCRIPTION_KA.md` | ეს ფაილი — სრული აღწერა |

### 1.7. ინფრასტრუქტურაში დამატებული სერვისები

- **Metabase** — `docker-compose.yml`-ში
- **Airflow + airflow-db** — უკვე იყო / გამოყენებულია K-Means-ისთვის
- **Zookeeper + MinIO** — სტეკის ნაწილი (Kafka კოორდინაცია + Lakehouse storage)

---

## 2. პროექტის დეტალური აღწერა

### 2.1. მიზანი

პროექტის მიზანია **რეალურ დროში** გადაიტანოს ოპერაციული (OLTP) ცვლილებები ანალიტიკურ Lakehouse-ში და უზრუნველყოს:

1. **Streaming CDC pipeline** — PostgreSQL → ანალიტიკა წამებში  
2. **Dimensional modeling** — Bronze + Gold (star schema)  
3. **SQL / BI ანალიტიკა** — Presto + Metabase  
4. **Batch ML** — Airflow + Python K-Means კლიენტების სეგმენტაციისთვის  
5. **გაზომვადი ექსპერიმენტი** — end-to-end latency

### 2.2. პრობლემა, რომელსაც წყვეტს

კლასიკურ ETL-ში მონაცემი ხშირად **პაკეტურად** (მაგ. ღამით) იტვირთება. ბიზნესს სჭირდება, რომ ახალი შეკვეთა **რაც შეიძლება მალე** გამოჩნდეს ანგარიშებში.  
ამიტომ გამოყენებულია **CDC (Change Data Capture)** — კოპირდება არა მთელი ბაზა, არამედ **მხოლოდ ცვლილებები**.

### 2.3. საერთო არქიტექტურა

პროექტი აერთიანებს **ორ ტიპის pipeline-ს**:

```text
REAL-TIME (streaming)
=====================
PostgreSQL ─WAL─► Debezium ─► Kafka (+Zookeeper) ─► Flink
                                                      │
                                              Iceberg @ MinIO
                                              Bronze + Gold
                                                      │
                              ┌───────────────────────┼───────────────────┐
                              ▼                       ▼                   ▼
                           Presto                  Metabase         Airflow Trigger
                           (SQL)                   (BI)                   │
                                                                          ▼
                                                              Python K-Means
                                                                          │
                                                                          ▼
                                                      MinIO analytics/customer_clusters/
```

### 2.4. კომპონენტები დეტალურად

#### (1) PostgreSQL 15 — OLTP წყარო
- ბაზა: **AdventureWorks** (გამარტივებული subset)
- Schema-ები: `person`, `production`, `sales` (~10 ცხრილი)
- `wal_level=logical` — Debezium-ისთვის აუცილებელი
- ფაილი: `init.sql`

#### (2) Debezium — CDC
- კითხულობს WAL-ს `pgoutput` პლაგინით
- Connector: `adventureworks-connector`
- Kafka topic-ები: `aw.<schema>.<table>` (10 topic)
- ფაილი: `register-connector.json`

#### (3) Kafka + Zookeeper — Event Bus
- Kafka ინახავს CDC event-ებს
- Zookeeper უზრუნველყოფს broker-ების კოორდინაციას და metadata-ს

#### (4) Apache Flink — Stream Processing
- ერთი SQL job: `adventureworks-cdc-lakehouse`
- Checkpoint: **10 წამი**, `EXACTLY_ONCE`
- **Bronze**: ნედლი CDC სარკეები (`br_*`)
- **Gold**: star schema — `fact_sales_order_line` + dimensions
- ფაილი: `flink_job.sql`
- UI: http://localhost:8081

#### (5) Apache Iceberg + MinIO — Lakehouse
- Iceberg: open table format (ACID, upsert, snapshot, time travel)
- MinIO: S3-compatible object storage
- Bucket: `lakehouse-admin`
- Console: http://localhost:9001 (`admin` / `adminpassword`)

#### (6) PrestoDB — SQL ანალიტიკა
- კითხულობს Iceberg ცხრილებს MinIO-დან
- KPI პაკეტი: `sql/metrics/` (revenue, top products, territory, time travel და სხვ.)

#### (7) Metabase — BI
- ვიზუალური დეშბორდი Gold-ზე
- აჩვენებს იმავე მონაცემს, რასაც Presto CLI

#### (8) Airflow + Python K-Means — Batch ML
- Airflow: Trigger → `kmeans_customers.py`
- K-Means: 3 კლასტერი კლიენტებზე
- შედეგი: MinIO `analytics/customer_clusters/`

### 2.5. მონაცემთა მოდელი (Gold Star Schema)

**Fact (grain = order line):**  
`fact_sales_order_line`

**Dimensions:**
- `dim_customer`
- `dim_product`
- `dim_territory`
- `dim_salesperson`
- `dim_currency`
- `dim_date`

Medallion პრინციპი:
- **Bronze** = raw / audit  
- **Gold** = curated / analytics-ready  

### 2.6. როგორ მუშაობს end-to-end (ერთი შეკვეთის მაგალითი)

1. Postgres-ში კეთდება `INSERT` (შეკვეთა + ხაზი) — `demo-pipeline.ps1` ან `run-experiment.ps1`
2. Debezium იჭერს WAL ცვლილებას და წერს Kafka topic-ებში
3. Flink მოიხმარს event-ს, წერს Bronze-ს და Gold fact-ს
4. ~10–14 წამში ახალი ჩანაწერი ჩანს Presto/Metabase-ში
5. (სურვილისამებრ) Airflow-დან გაეშვება K-Means → კლასტერები MinIO-ში

### 2.7. ექსპერიმენტის შედეგი (გაზომილი)

| მეტრიკა | მნიშვნელობა |
|---------|-------------|
| End-to-end latency | **≈ 13.6 წამი** (ტიპიური დიაპაზონი 9–14 / 10–40s) |
| გზა | Postgres INSERT → Debezium → Kafka → Flink → Iceberg Gold → Presto |
| ანგარიში | `docs/experiment-results/latest.md` |

### 2.8. რა თვითონ მუშაობს და რა უნდა გაუშვა

| ავტომატური (მუდმივი) | ხელით |
|----------------------|--------|
| Postgres, Kafka, Debezium, Flink job, MinIO, Presto, Metabase | `demo-pipeline.ps1` (ახალი INSERT დემო) |
| | `run-experiment.ps1` (latency გაზომვა) |
| | Airflow Trigger / K-Means |
| | პირველად: connector register + Flink submit |

### 2.9. სერვისების URL-ები

| სერვისი | URL | ლოგინი |
|---------|-----|--------|
| Flink | http://localhost:8081 | — |
| MinIO | http://localhost:9001 | admin / adminpassword |
| Presto | http://localhost:8080 | — |
| Airflow | http://localhost:8085 | admin / admin |
| Metabase | http://localhost:3000 | admin@adventureworks.local / Admin123! |
| Kafka Connect | http://localhost:8083 | — |

### 2.10. მთავარი ფაილები

| ფაილი | როლი |
|-------|------|
| `docker-compose.yml` | ყველა სერვისი |
| `init.sql` | AdventureWorks schema + seed |
| `register-connector.json` | Debezium connector |
| `flink_job.sql` | Bronze + Gold streaming |
| `demo-pipeline.ps1` | CDC დემო |
| `scripts/run-experiment.ps1` | latency + KPI report |
| `analytics/kmeans_customers.py` | K-Means |
| `airflow/dags/lakehouse_kmeans_dag.py` | Airflow DAG |
| `sql/metrics/*.sql` | ანალიტიკური მოთხოვნები |

---

## 3. დაცვისთვის მოკლე დასკვნა (1 აბზაცი)

პროექტი აერთიანებს **real-time CDC pipeline-ს** (PostgreSQL → Debezium → Kafka → Flink → Iceberg/MinIO) და **batch ანალიტიკურ ფენას** (Airflow + Python K-Means). Lakehouse-ში მონაცემი ინახება Bronze/Gold (star schema) სახით; ანალიტიკა ხელმისაწვდომია Presto SQL-ით და Metabase დეშბორდით. ექსპერიმენტში ახალი შეკვეთა Gold ფენაში **დაახლოებით 10–14 წამში** გამოჩნდა, რაც ადასტურებს streaming pipeline-ის ეფექტურობას ლოკალურ დემო გარემოში.

---

## 4. ჩამატებების მოკლე ჩამონათვალი (სლაიდისთვის)

1. **Airflow** — batch orchestration  
2. **Python + MinIO** — Gold Parquet-ის ანალიზი  
3. **K-Means** — კლიენტების სეგმენტაცია (K=3)  
4. **Metabase** — BI დეშბორდი  
5. **Latency ექსპერიმენტი** — გაზომილი შედეგი (~13.6s)  
6. **დოკუმენტაცია / სქემები** — არქიტექტურა, BI, experiment, Mermaid diagrams  
