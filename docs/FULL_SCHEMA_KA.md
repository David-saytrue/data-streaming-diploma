# პროექტის მაქსიმალურად დეტალური სქემა

გახსენი **https://mermaid.live** → ჩასვი **ერთი** `mermaid` ბლოკი ერთდროულად (მთელი ფაილი ერთად არ ჩასვა).

ფაილი: `docs/FULL_SCHEMA_KA.md`

---

# A. სრული არქიტექტურა (ყველა კომპონენტი + პორტები)

```mermaid
flowchart TB
  subgraph HOST["შენი კომპიუტერი — Docker Compose"]
    subgraph S1["LAYER 1 — OLTP წყარო"]
      PG[("PostgreSQL 15<br/>:5432<br/>DB: adventureworks<br/>user: postgres<br/>wal_level=logical")]
      INIT["init.sql<br/>schemas: person, production, sales<br/>~10 ცხრილი + seed data"]
      INIT --> PG
    end

    subgraph S2["LAYER 2 — CDC"]
      DBZ["Debezium Connect 2.4<br/>:8083<br/>connector: adventureworks-connector<br/>plugin: pgoutput<br/>slot: aw_slot<br/>publication: aw_publication"]
    end

    subgraph S3["LAYER 3 — Event Bus"]
      ZK["Zookeeper 2.4<br/>:2181"]
      KF["Kafka 2.4<br/>:9092<br/>topic.prefix = aw"]
      ZK -.->|broker metadata<br/>კოორდინაცია| KF
    end

    subgraph S4["LAYER 4 — Stream Processing"]
      JM["Flink JobManager<br/>:8081 UI"]
      TM["Flink TaskManager<br/>slots=2"]
      SQL["flink_job.sql<br/>pipeline.name =<br/>adventureworks-cdc-lakehouse<br/>checkpoint = 10s EXACTLY_ONCE"]
      JM --- TM
      SQL --> JM
    end

    subgraph S5["LAYER 5 — Lakehouse Storage"]
      IC["Apache Iceberg 1.4.3<br/>format-version 2<br/>write.upsert.enabled=true<br/>catalog-type=hadoop"]
      MN[("MinIO<br/>API :8333→9000<br/>Console :9001<br/>bucket: lakehouse-admin<br/>admin / adminpassword")]
      IC --- MN
    end

    subgraph S6["LAYER 6 — Query + BI"]
      PR["PrestoDB<br/>:8080<br/>catalog: iceberg<br/>schema: gold / bronze"]
      MB["Metabase v0.49<br/>:3000<br/>admin@adventureworks.local<br/>Dashboard: AdventureWorks Sales"]
    end

    subgraph S7["LAYER 7 — Batch Orchestration + ML"]
      AFDB[("Airflow Postgres<br/>metadata DB")]
      AF["Airflow 2.8.1<br/>:8085<br/>admin / admin<br/>DAG: lakehouse_customer_kmeans<br/>schedule=None → ხელით Trigger"]
      PY["Python 3.11<br/>kmeans_customers.py<br/>pandas + sklearn + boto3"]
      AFDB --- AF
      AF -->|BashOperator| PY
    end
  end

  PG -->|"1. WAL logical decoding"| DBZ
  DBZ -->|"2. CDC JSON events"| KF
  KF -->|"3. consume topics"| JM
  JM -->|"4a. Bronze mirrors"| IC
  JM -->|"4b. Gold star schema"| IC
  IC -->|"Parquet + metadata"| MN
  MN <-->|"5. SQL read"| PR
  PR -->|"6. native SQL cards"| MB
  MN -->|"7. Gold fact Parquet"| PY
  PY -->|"8. clusters CSV/Parquet"| MN
```

---

# B. ერთი INSERT-ის სრული გზა (რა ხდება შიგნით)

```mermaid
sequenceDiagram
  autonumber
  actor U as შენ
  participant Demo as demo-pipeline.ps1<br/>ან run-experiment.ps1
  participant PG as PostgreSQL
  participant WAL as WAL / pgoutput
  participant DBZ as Debezium
  participant KF as Kafka
  participant FL as Flink SQL Job
  participant BR as Iceberg Bronze
  participant GD as Iceberg Gold
  participant MN as MinIO files
  participant PR as Presto
  participant MB as Metabase

  U->>Demo: გაშვება
  Demo->>PG: INSERT sales_order_header + detail<br/>(product_id=11, qty=2, GEL)
  PG->>WAL: ჩაწერა LSN-ზე
  WAL->>DBZ: replication slot aw_slot
  DBZ->>DBZ: Envelope: op=c, after={...}
  DBZ->>KF: aw.sales.sales_order_header
  DBZ->>KF: aw.sales.sales_order_detail
  KF->>FL: kafka source tables<br/>format=debezium-json
  FL->>FL: CAST decimals, TO_TIMESTAMP_LTZ
  FL->>BR: INSERT br_sales_order_header/detail
  FL->>GD: JOIN header⋈detail → fact_sales_order_line
  Note over FL,MN: checkpoint ~10s → Iceberg snapshot commit
  FL->>MN: s3a://lakehouse-admin/iceberg_data/.../*.parquet
  Demo->>PR: SELECT ... FROM gold.fact_sales_order_line
  PR->>MN: წაიკითხე Parquet
  PR-->>Demo: ახალი sales_order_id ჩანს
  MB->>PR: dashboard refresh
  PR-->>MB: KPI / Recent Orders განახლდება
```

---

# C. PostgreSQL წყარო — ყველა ცხრილი

```mermaid
erDiagram
  PERSON ||--o{ CUSTOMER : "person_id"
  PERSON ||--o{ SALES_PERSON : "business_entity_id"
  TERRITORY ||--o{ CUSTOMER : "territory_id"
  TERRITORY ||--o{ SALES_PERSON : "territory_id"
  TERRITORY ||--o{ ORDER_HEADER : "territory_id"
  CURRENCY ||--o{ ORDER_HEADER : "currency_code"
  CUSTOMER ||--o{ ORDER_HEADER : "customer_id"
  SALES_PERSON ||--o{ ORDER_HEADER : "sales_person_id"
  ORDER_HEADER ||--|{ ORDER_DETAIL : "sales_order_id"
  PRODUCT_CATEGORY ||--|{ PRODUCT_SUBCATEGORY : "category_id"
  PRODUCT_SUBCATEGORY ||--|{ PRODUCT : "subcategory_id"
  PRODUCT ||--o{ ORDER_DETAIL : "product_id"

  PERSON {
    int business_entity_id PK
    string person_type
    string first_name
    string last_name
    string email_address
  }
  PRODUCT_CATEGORY {
    int product_category_id PK
    string name
  }
  PRODUCT_SUBCATEGORY {
    int product_subcategory_id PK
    int product_category_id FK
    string name
  }
  PRODUCT {
    int product_id PK
    int product_subcategory_id FK
    string name
    string product_number
    decimal list_price
  }
  TERRITORY {
    int territory_id PK
    string name
    string country_region
    string group
  }
  CURRENCY {
    string currency_code PK
    string name
  }
  CUSTOMER {
    int customer_id PK
    int person_id FK
    int territory_id FK
    string account_number
    string customer_segment
  }
  SALES_PERSON {
    int business_entity_id PK
    int territory_id FK
    decimal sales_quota
    decimal commission_pct
  }
  ORDER_HEADER {
    int sales_order_id PK
    timestamp order_date
    int customer_id FK
    int sales_person_id FK
    int territory_id FK
    string currency_code FK
    decimal total_due
  }
  ORDER_DETAIL {
    int sales_order_detail_id PK
    int sales_order_id FK
    int product_id FK
    smallint order_qty
    decimal unit_price
    decimal line_total
  }
```

**Schemas:** `person` | `production` | `sales`  
**ფაილი:** `init.sql`

---

# D. Debezium → Kafka topics (1:1 ცხრილთან)

```mermaid
flowchart LR
  subgraph PG["PostgreSQL tables"]
    P1[person.person]
    P2[production.product_category]
    P3[production.product_subcategory]
    P4[production.product]
    P5[sales.sales_territory]
    P6[sales.currency]
    P7[sales.customer]
    P8[sales.sales_person]
    P9[sales.sales_order_header]
    P10[sales.sales_order_detail]
  end

  subgraph KF["Kafka topics — prefix aw"]
    T1[aw.person.person]
    T2[aw.production.product_category]
    T3[aw.production.product_subcategory]
    T4[aw.production.product]
    T5[aw.sales.sales_territory]
    T6[aw.sales.currency]
    T7[aw.sales.customer]
    T8[aw.sales.sales_person]
    T9[aw.sales.sales_order_header]
    T10[aw.sales.sales_order_detail]
  end

  P1 --> T1
  P2 --> T2
  P3 --> T3
  P4 --> T4
  P5 --> T5
  P6 --> T6
  P7 --> T7
  P8 --> T8
  P9 --> T9
  P10 --> T10
```

**კონფიგი:** `register-connector.json`  
- `snapshot.mode=initial` — პირველად მთელი ცხრილი  
- შემდეგ მხოლოდ ცვლილებები (op: c/u/d)  
- `decimal.handling.mode=string`

---

# E. Flink შიგნით — Kafka → Bronze → Gold

```mermaid
flowchart TB
  subgraph KAFKA_SRC["Flink Kafka source tables (default catalog)"]
    K1[kafka_person]
    K2[kafka_product_category]
    K3[kafka_product_subcategory]
    K4[kafka_product]
    K5[kafka_sales_territory]
    K6[kafka_currency]
    K7[kafka_customer]
    K8[kafka_sales_person]
    K9[kafka_sales_order_header]
    K10[kafka_sales_order_detail]
  end

  subgraph BRONZE["Iceberg Bronze — 1:1 raw mirrors"]
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

  subgraph GOLD_DIM["Iceberg Gold — Dimensions"]
    DC[dim_customer<br/>customer ⋈ person ⋈ territory]
    DP[dim_product<br/>product ⋈ subcategory ⋈ category]
    DT[dim_territory]
    DS[dim_salesperson<br/>salesperson ⋈ person ⋈ territory]
    DCur[dim_currency]
    DD[dim_date<br/>ერთჯერადი Presto SQL]
  end

  subgraph GOLD_FACT["Iceberg Gold — Fact"]
    F[fact_sales_order_line<br/>header ⋈ detail<br/>grain: order line]
  end

  K1 --> B1
  K2 --> B2
  K3 --> B3
  K4 --> B4
  K5 --> B5
  K6 --> B6
  K7 --> B7
  K8 --> B8
  K9 --> B9
  K10 --> B10

  K7 --> DC
  K1 --> DC
  K5 --> DC
  K4 --> DP
  K3 --> DP
  K2 --> DP
  K5 --> DT
  K8 --> DS
  K1 --> DS
  K5 --> DS
  K6 --> DCur
  K9 --> F
  K10 --> F
```

**ფაილი:** `flink_job.sql`  
**ერთი job:** `EXECUTE STATEMENT SET` — ყველა INSERT ერთად, atomic checkpoint.

---

# F. Gold Star Schema (ანალიტიკური მოდელი)

```mermaid
flowchart TB
  F["FACT: fact_sales_order_line<br/>PK: sales_order_id + sales_order_detail_id<br/>measures: order_qty, unit_price, discount, line_total, gross_amount"]

  DC["dim_customer<br/>customer_id, full_name, segment, territory"]
  DP["dim_product<br/>product_id, name, category, subcategory, prices"]
  DT["dim_territory<br/>territory_id, name, country, group"]
  DS["dim_salesperson<br/>sales_person_id, name, quota, commission"]
  DCur["dim_currency<br/>currency_code, name"]
  DD["dim_date<br/>full_date, day_name, month, year..."]

  DC --> F
  DP --> F
  DT --> F
  DS --> F
  DCur --> F
  DD --> F
```

**Fact ველები (მთავარი):**  
`sales_order_id`, `sales_order_detail_id`, `order_ts`, `customer_id`, `product_id`, `territory_id`, `sales_person_id`, `currency_code`, `order_qty`, `unit_price`, `unit_price_discount`, `gross_amount`, `discount_amount`, `line_total`

---

# G. MinIO ფიზიკური სტრუქტურა

```mermaid
flowchart TB
  BUCKET["bucket: lakehouse-admin"]

  BUCKET --> ICE["iceberg_data/"]
  BUCKET --> AN["analytics/"]

  ICE --> BR["bronze/<br/>br_person, br_product, ...<br/>data/*.parquet + metadata/"]
  ICE --> GD["gold/<br/>fact_sales_order_line/<br/>dim_customer, dim_product, ...<br/>data/*.parquet + metadata/"]

  AN --> CL["customer_clusters/<br/>run_ts=YYYYMMDDTHHMMSSZ/<br/>customer_clusters.parquet<br/>customer_clusters.csv"]
```

**Console:** http://localhost:9001  
**Flink წერს:** `s3a://lakehouse-admin/iceberg_data/`  
**K-Means წერს:** `s3://lakehouse-admin/analytics/customer_clusters/`

---

# H. Batch ML დეტალურად (Airflow + Python + K-Means)

```mermaid
flowchart TB
  subgraph TRIGGER["გაშვება — თვითონ არა!"]
    UI["Airflow UI :8085<br/>DAG: lakehouse_customer_kmeans<br/>ღილაკი: Trigger"]
    CLI["ან ტერმინალი:<br/>docker exec ... python kmeans_customers.py"]
  end

  subgraph AF["Airflow"]
    DAG["DAG schedule=None<br/>retries=1"]
    BASH["BashOperator<br/>task: kmeans_customers_minio"]
    DAG --> BASH
  end

  subgraph PY["kmeans_customers.py"]
    S3["boto3 → MinIO<br/>list Gold fact Parquet"]
    RD["pandas read_parquet"]
    FEAT["groupby customer_id → features:<br/>order_lines<br/>total_revenue<br/>avg_line_value<br/>unique_products"]
    SC["StandardScaler"]
    KM["KMeans n_clusters=3<br/>random_state=42"]
    OUT["write Parquet + CSV"]
    S3 --> RD --> FEAT --> SC --> KM --> OUT
  end

  subgraph RES["შედეგი"]
    MN2["MinIO analytics/customer_clusters/"]
    CSV["Excel-ში გახსნა:<br/>customer_id + cluster 0/1/2"]
  end

  UI --> DAG
  CLI --> PY
  BASH --> PY
  OUT --> MN2 --> CSV
```

**რისთვის:** კლიენტების სეგმენტაცია (მცირე / საშუალო / VIP ტიპის ჯგუფები).  
**სად ვნახო:** MinIO, **არა** Metabase.

---

# I. BI ფენა (Presto + Metabase) დეტალურად

```mermaid
flowchart LR
  MN[(MinIO Gold Parquet)] --> PR[Presto<br/>catalog=iceberg<br/>schema=gold]
  PR --> MB[Metabase]

  subgraph CARDS["Dashboard: AdventureWorks Sales"]
    C1[KPI Total Revenue — scalar]
    C2[Revenue by Day — line]
    C3[Top Products — bar]
    C4[Revenue by Territory — row]
    C5[Recent Orders CDC — table]
  end

  MB --> C1
  MB --> C2
  MB --> C3
  MB --> C4
  MB --> C5

  subgraph SQLPACK["sql/metrics/ — Presto CLI"]
    M1[01 revenue by day]
    M2[02 revenue by month]
    M3[03 top products]
    M4[04 AOV basket]
    M5[05 territory]
    M6[06 discount]
    M7[07 salesperson]
    M8[08 time travel]
  end

  PR --> SQLPACK
```

**Metabase ≠ K-Means.**  
Metabase = გაყიდვების ნახვა.  
K-Means = კლიენტების კლასტერები MinIO-ში.

---

# J. რა თვითონ მუშაობს vs რა უნდა გაუშვა

```mermaid
flowchart TB
  subgraph ALWAYS["მუდმივად მუშაობს docker compose up-ის შემდეგ"]
    A1[Zookeeper]
    A2[Kafka]
    A3[PostgreSQL]
    A4[Debezium Connect]
    A5[Flink JM + TM — თუ job უკვე submitted]
    A6[MinIO]
    A7[Presto]
    A8[Metabase]
    A9[Airflow webserver — მაგრამ DAG არ გაეშვება თავისით]
  end

  subgraph ONCE["ერთჯერადი / ხელით"]
    O1[register-connector.json → POST :8083]
    O2[flink_job.sql submit]
    O3[dim_date.sql Presto-ში]
    O4[demo-pipeline.ps1 — INSERT დემო]
    O5[run-experiment.ps1 — latency გაზომვა]
    O6[Airflow Trigger — K-Means]
    O7[configure-metabase.ps1 — პირველი setup]
  end

  ALWAYS --> O4
  O2 --> ALWAYS
  O1 --> ALWAYS
  O6 --> OUT["MinIO clusters"]
  O4 --> GOLD["Gold ახალი რიგები"]
  O5 --> REP["docs/experiment-results/latest.md"]
```

---

# K. სკრიპტები და რა აკეთებენ

```mermaid
flowchart LR
  subgraph SCRIPTS["სკრიპტები"]
    SA[start-all.ps1<br/>სრული სტარტი 1→6]
    SD[demo-pipeline.ps1<br/>INSERT + Kafka + Bronze/Gold preview]
    SE[scripts/run-experiment.ps1<br/>latency + KPI report]
    SM[scripts/setup-metabase.ps1<br/>ინსტრუქცია]
    SC[scripts/configure-metabase.ps1<br/>API: admin+DB+dashboard]
  end

  SA --> SD
  SA --> SE
  SD --> PG[(Postgres change)]
  SE --> MD[experiment-results/latest.md]
  SC --> MB[Metabase ready]
```

| სკრიპტი | რას აკეთებს | შედეგი სად |
|---------|-------------|------------|
| `docker compose up -d` | ყველა კონტეინერი | პორტები |
| `demo-pipeline.ps1` | CDC დემო INSERT | ტერმინალი + Gold |
| `run-experiment.ps1` | latency გაზომვა | `docs/experiment-results/` |
| Airflow Trigger | K-Means | MinIO `analytics/` |
| Metabase | BI ნახვა | http://localhost:3000/dashboard/1 |

---

# L. პორტების რუკა

```mermaid
flowchart TB
  USER[ბრაუზერი / psql / CLI]

  USER --> F8081[8081 Flink UI]
  USER --> M9001[9001 MinIO Console]
  USER --> P8080[8080 Presto]
  USER --> A8085[8085 Airflow]
  USER --> B3000[3000 Metabase]
  USER --> C8083[8083 Kafka Connect API]
  USER --> G5432[5432 Postgres]
  USER --> K9092[9092 Kafka]
  USER --> Z2181[2181 Zookeeper]
  USER --> S8333[8333 MinIO S3 API]
```

---

# M. პრეზენტაციის ერთი სლაიდი — „რა რატომ“

```mermaid
mindmap
  root((Diploma Pipeline))
    Real-time CDC
      PostgreSQL WAL
      Debezium
      Kafka + Zookeeper
      Flink streaming SQL
    Lakehouse
      Iceberg format v2
      MinIO object storage
      Bronze raw
      Gold star schema
    Analytics BI
      Presto SQL
      Metabase dashboard
      metrics SQL pack
      time travel
    Batch ML
      Airflow orchestration
      Python pandas sklearn
      K-Means K=3
      clusters on MinIO
    Experiment
      INSERT demo
      latency 10-14s
      report markdown
```

---

# N. მოკლე ლექსიკონი (დაცვაზე)

| ტერმინი | მნიშვნელობა შენს პროექტში |
|---------|---------------------------|
| **CDC** | Change Data Capture — მხოლოდ ცვლილებების კოპირება |
| **WAL** | Postgres-ის ტრანზაქციის ლოგი, საიდანაც Debezium კითხულობს |
| **Bronze** | ნედლი CDC სარკე, აუდიტისთვის |
| **Gold** | გაწმენდილი/მოდელირებული star schema ანალიტიკისთვის |
| **Iceberg** | ცხრილის ფორმატი Parquet-ზე (ACID, snapshot, time travel) |
| **MinIO** | S3-compatible დისკი/storage |
| **Flink** | streaming ძრავა — მუდმივად ამუშავებს event-ებს |
| **Airflow** | batch job-ის **გაშვების** მენეჯერი (არა ანალიზი) |
| **K-Means** | კლიენტების დაჯგუფება K ჯგუფად |
| **Metabase** | BI დეშბორდი Gold-ზე |
| **Presto** | SQL ძრავა Lakehouse-ზე |
| **Zookeeper** | Kafka-ს კოორდინატორი |

---

# O. რეკომენდებული ჩასმა mermaid.live-ზე (რიგით)

1. **A** — სრული არქიტექტურა (მთავარი სლაიდი)  
2. **B** — INSERT sequence (დემოს ახსნა)  
3. **F** — Star schema  
4. **H** — Airflow/K-Means  
5. **I** — Metabase  
6. **J** — რა ავტომატურია / რა ხელითაა  

დანარჩენი (C, D, E, G, K…) — დანართი / დოკუმენტაცია.
