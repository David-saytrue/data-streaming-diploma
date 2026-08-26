# დიაგრამების კოდი — ჩასვი mermaid.live-ზე

გახსენი https://mermaid.live  
დააკოპირე **ერთი** ბლოკი (მხოლოდ კოდი, სამი backtick-ის გარეშე თუ საიტი თავად ითხოვს plain text).

ეს არის შენი ძველი 2 სურათის **განახლებული** ვერსია (დამატებულია: Zookeeper, MinIO, Airflow, Python K-Means, Metabase).

---

## 1) მარტივი ჰორიზონტალური (შენი მეორე სურათის მსგავსი)

```mermaid
flowchart LR
  PG["PostgreSQL<br/>Transaction DB"]
  DBZ["Debezium<br/>CDC Connector"]
  KF["Apache Kafka<br/>Message Broker"]
  FL["Apache Flink<br/>Stream Processor"]
  IC["Apache Iceberg<br/>Open Table Format"]
  MN["MinIO<br/>S3 Storage"]
  PR["PrestoDB<br/>Query Engine"]
  MB["Metabase<br/>BI Dashboard"]
  AF["Airflow<br/>Orchestration"]
  PY["Python K-Means<br/>Customer ML"]

  PG -->|"WAL Change Events"| DBZ
  DBZ -->|"Streaming Events"| KF
  KF --> FL
  FL --> IC
  IC --> MN
  MN -->|"SQL Analytics"| PR
  PR --> MB
  MN --> PY
  AF -->|"Trigger"| PY
  PY -->|"clusters"| MN
```

---

## 2) დეტალური 6+ ფენა (შენი პირველი სურათის მსგავსი, სრული)

```mermaid
flowchart LR
  subgraph L1["1 SOURCE"]
    PG["PostgreSQL 15<br/>adventureworks<br/>wal_level=logical"]
    TABS["10 tables:<br/>person.person<br/>production.product_category<br/>production.product_subcategory<br/>production.product<br/>sales.sales_territory<br/>sales.currency<br/>sales.customer<br/>sales.sales_person<br/>sales.sales_order_header<br/>sales.sales_order_detail"]
    PG --- TABS
  end

  subgraph L2["2 CDC"]
    DBZ["Debezium<br/>Postgres Connector<br/>pgoutput / aw_slot"]
    ZK["Zookeeper :2181"]
    KF["Apache Kafka :9092<br/>10 topics aw.*"]
    ZK -.-> KF
    DBZ --> KF
  end

  subgraph L3["3 STREAMING"]
    JM["Flink JobManager :8081"]
    TM["Flink TaskManager"]
    JOB["flink_job.sql<br/>EXECUTE STATEMENT SET<br/>checkpoint 10s"]
    JM --- TM
    JOB --> JM
  end

  subgraph L4["4 STORAGE"]
    MN["MinIO S3<br/>bucket: lakehouse-admin<br/>Console :9001"]
  end

  subgraph L5["5 LAKEHOUSE Iceberg"]
    BR["BRONZE 10 mirrors<br/>br_person ... br_sales_order_detail"]
    GD["GOLD star schema<br/>fact_sales_order_line<br/>+ 6 dimensions"]
  end

  subgraph L6["6 ANALYTICS"]
    PR["PrestoDB :8080<br/>SQL on Iceberg"]
    MB["Metabase :3000<br/>Dashboard KPIs"]
    KPI["Revenue / Top-N<br/>Territory / Time Travel"]
    PR --> MB
    PR --- KPI
  end

  subgraph L7["7 BATCH ML"]
    AF["Airflow :8085<br/>DAG Trigger"]
    PY["Python<br/>kmeans_customers.py"]
    KM["K-Means K=3<br/>customer clusters"]
    AF --> PY --> KM
  end

  L1 -->|"WAL"| DBZ
  KF -->|"consume"| L3
  L3 -->|"write Parquet"| L5
  L5 --> L4
  L4 <-->|"read"| PR
  L4 -->|"Gold Parquet"| PY
  KM -->|"CSV/Parquet"| L4
```

---

## 3) Lakehouse შიგნით — Bronze + Gold Star (პირველი სურათის ცენტრი)

```mermaid
flowchart TB
  subgraph BRONZE["BRONZE - Raw CDC mirrors"]
    B1[br_person]
    B2[br_product_category]
    B3[br_product_subcategory]
    B4[br_product]
    B5[br_sales_territory]
    B6[br_currency]
    B7[br_customer]
    B8[br_sales_person]
    B9[br_sales_order_header]
    B10[br_sales_order_detail]
  end

  subgraph GOLD["GOLD - Star Schema"]
    F["fact_sales_order_line"]
    DC[dim_customer]
    DP[dim_product]
    DT[dim_territory]
    DS[dim_salesperson]
    DCur[dim_currency]
    DD[dim_date]
    DC --> F
    DP --> F
    DT --> F
    DS --> F
    DCur --> F
    DD --> F
  end

  BRONZE -.->|"Flink also builds Gold<br/>from Kafka joins"| GOLD
```

---

## 4) რა შეიცვალა ძველ სურათთან შედარებით

ძველ დიაგრამებში **არ იყო** / უნდა დაემატოს:

| დამატება | რატომ |
|----------|--------|
| **Zookeeper** | Kafka-ს კოორდინაცია |
| **MinIO** ცალკე storage ფენად | Iceberg ფაილები აქაა |
| **Airflow** | batch გაშვება |
| **Python K-Means** | კლიენტების სეგმენტაცია |
| **Metabase** | BI დეშბორდი Presto-ზე |

ძველ სურათში შეცდომა/განსხვავება:
- `address` ცხრილი **არ გაქვს** — წაშალე სიიდან
- Iceberg ცხრილები: Bronze 10 + Gold 7 (fact + 6 dim) ≈ **17**, არა აუცილებლად „16“

---

## 5) თუ Eraser / FigJam / draw.io-ში ხელით ხატავ

ტექსტური ბლოკები იგივე თანმიმდევრობით:

```
PostgreSQL (adventureworks, 10 tables, WAL)
    → Debezium (CDC, pgoutput)
    → Kafka (+ Zookeeper)  [10 topics aw.*]
    → Flink SQL (Bronze + Gold, checkpoint 10s)
    → Iceberg on MinIO (lakehouse-admin)
         ├─ Bronze: br_*
         └─ Gold: fact + dims
    → Presto → Metabase (BI)
    → Airflow Trigger → Python K-Means → MinIO analytics/customer_clusters/
```
