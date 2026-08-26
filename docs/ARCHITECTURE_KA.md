# არქიტექტურა და კომპონენტების ახსნა (დიპლომი)

## სრული სურათი

```text
                    REAL-TIME (streaming)
                    =====================
PostgreSQL ──WAL──► Debezium ──► Kafka ──► Flink ──► Iceberg ──► MinIO
   [OLTP]              [CDC]      [bus]    [stream]   [format]  [storage]
                                                              │
                    BATCH / ML (orchestrated)                   │
                    ========================                    │
                         Airflow DAG ◄──────────────────────────┘
                              │
                              ▼
                    Python + K-Means (sklearn)
                              │
                              ▼
                    MinIO: analytics/customer_clusters/
```

| # | კომპონენტი | როლი |
|---|------------|------|
| 1 | PostgreSQL | ოპერაციული ბაზა — ცვლილებები აქ ხდება |
| 2 | Debezium | CDC — WAL-იდან event-ები |
| 3 | Kafka | event ბურთული |
| 3a | **Zookeeper** | Kafka-ს კოორ�dinaciა (იხ. ქვემოთ) |
| 4 | Flink | streaming SQL → Bronze + Gold |
| 5 | Iceberg + **MinIO** | Lakehouse ფორმატი + ფიზიკური storage |
| 6 | Presto | SQL ანალი�tics Lakehouse-ზე |
| 7 | **Airflow** | batch job-ების დაგეგმვა/გაშვება |
| 8 | **Python K-Means** | ML ანალიზი MinIO-დან წაკითხული Gold Parquet-ზე |
| 9 | **Metabase** | BI დეშბორდი Presto → Iceberg Gold-ზე |

---

## რატომ გვჭირდება Zookeeper?

**Zookeeper** არის Kafka-ის **კოორდინატორი** (klassiuri Kafka + Zookeeper არქიტექტურა).

```text
Zookeeper (:2181)
    │
    ├── broker-ების რეგისტრაცია (kafka-1 ცოცხალია თუ არა)
    ├── topic / partition metadata
    └── consumer group offset-ები (legacy mode)
         │
         ▼
      Kafka (:9092)  ◄── Debezium, Flink
```

**რატომ არის პროექტში:**
- `quay.io/debezium/kafka:2.4` image **Zookeeper-ზეა აგებული**
- `docker-compose.yml`-ში: `ZOOKEEPER_CONNECT=zookeeper:2181`
- Debezium topic-ები (`aw.sales.*`) და Flink consumer-ები **Kafka-ს** იყენებენ → Kafka **Zookeeper-ს** სჭირდება

**დიპლომში ერთი წინადადება:**
> Zookeeper უზრუნველყოფს Apache Kafka კластერის მეტამონაცემების და broker-ების კოორ�dinaciას; CDC event-ების გადაცემა Debezium-დან Flink-ამდე Kafka-ს გარეშე შეუძლებელია, ამიტომ Zookeeper ინფრასტრუქტურის სავალდებულო ნაწილია.

**შენიშვნა:** ახალი Kafka (KRaft) Zookeeper-ის გარეშე მუშაობს, მაგრამ Debezium demo stack-ში ჯერ კიდევ Zookeeper სტანდარტია.

---

## რატომ გვჭირდება MinIO?

**MinIO** = **S3-თან თავსებადი object storage** (ფაილები „bucket“-ებში).

```text
Flink ──writes──► s3a://lakehouse-admin/iceberg_data/
                         │
                         ├── bronze/br_*/data/*.parquet
                         ├── gold/fact_*/data/*.parquet
                         └── metadata/ (Iceberg snapshots)
                         │
Presto ──reads──► იგივე path (hive.s3.endpoint=minio:9000)
                         │
Python/Airflow ──reads──► Gold Parquet + writes analytics/
```

**რატომ არა პირდაპირ დისკი:**
- **Iceberg** cloud-native ფორმატია — S3/MinIO-ზეა გათვლილი
- **Flink** და **Presto** უკვე S3A კონფიგით (`s3.endpoint`, access key)
- **ცალკე storage** ingestion-ისგან — Lakehouse პრინციპი

**Console:** http://localhost:9001 (`admin` / `adminpassword`)

**დიპლომში:**
> MinIO ინახავს Lakehouse-ის Parquet ფაილებს და Iceberg metadata-ს S3-თან თავსებად API-ით, რაც Flink-ის ჩაწერას და Presto/Python-ის წაკითხვას ერთ საერთო storage-ზე აერთიანებს.

---

## რატომ დავამატეთ Airflow? (lecturer-ის მოთხოვნა)

**Flink** = **real-time** (streaming, წამებში).  
**Airflow** = **batch orchestration** (როდის, რა თანმიმდევრობით გაეშვას job).

```text
Flink:     მუდმივად მუშაობს, CDC → Gold
Airflow:   DAG trigger → Python K-Means (მაგ. დღიურად ან ხელით demo-ზე)
```

**რას აკეთებს DAG `lakehouse_customer_kmeans`:**
1. Airflow UI-დან trigger
2. BashOperator → `kmeans_customers.py`
3. შედეგი MinIO-ში: `analytics/customer_clusters/`

**UI:** http://localhost:8085 (`admin` / `admin`)

**დიპლომში:**
> Apache Airflow უზრუნველყოფს batch ანალიტიკური pipeline-ის ორკესტრაციას Lakehouse-ის შევსების შემდეგ, გამოიყოფა streaming (Flink) და batch (Airflow) ფენები.

---

## რატომ K-Means? (lecturer-ის მოთხოვნა)

**K-Means** — არაუკვე ზედმიწევნითი კლastering: მონაცემები K ჯგუფად იყოფა.

**წყარო:** Gold `fact_sales_order_line` Parquet (MinIO).

**customer_id-ზე აგრეგაცია:**
| feature | აღწერა |
|---------|--------|
| order_lines | რამდენი ხაზი იყიდა |
| total_revenue | ჯამური შემოსავალი |
| avg_line_value | საშუალო ხაზის ღირებულება |
| unique_products | განსხვავებული პროდუქტი |

**K=3** → 3 კლიენტის სეგმენტი (მაგ. „მცირე“, „საშუალო“, „VIP“).

**შედეგი:** `lakehouse-admin/analytics/customer_clusters/` (Parquet + CSV)

**დიპლომში:**
> Gold ფენის გაყიდვების ფაქტებზე K-Means კლastering-ით მომხმარებლები სეგментირდება შეძენის ქცევის მიხედვით; ანალიზი Python-ით ხორციელდება MinIO-ზე შენახული Parquet ფაილებიდან, orchestration-ს Airflow ახორციელებს.

---

## გაშვების რიგი (სრული)

```powershell
# 1. ინფრასტრუქტურა
docker compose up -d

# 2. Real-time CDC + Lakehouse (INSERT დემო)
.\demo-pipeline.ps1 -SkipInfra

# 3. ექსპერიმენტი: latency გაზომვა + KPI ანგარიში (იგივე INSERT გზა)
.\scripts\run-experiment.ps1

# 4. K-Means (პირდაპირ ან Airflow UI http://localhost:8085)
docker exec data-streaming-diploma-airflow-1 python /opt/airflow/analytics/kmeans_customers.py

# 5. BI დეშბორდი
.\scripts\setup-metabase.ps1
# http://localhost:3000 — იხ. docs/BI_DASHBOARD_KA.md
```

დეტალები: [EXPERIMENT_KA.md](EXPERIMENT_KA.md), [BI_DASHBOARD_KA.md](BI_DASHBOARD_KA.md)

---

## ლექტორთან დასაბუთება — ერთი აბზაცი

პროექტი აერთიანებს **ორი ტიპის data pipeline-ს**: (1) **real-time CDC** PostgreSQL-იდან Debezium/Kafka/Flink გზით Iceberg Lakehouse-ში MinIO-ზე; (2) **batch ML ანალიტიკა** Airflow-ის ორკესტრაციით, Python K-Means სკრიპტით Gold Parquet-ის წაკითხვაზე. Zookeeper უზრუნველყოფს Kafka-ს სტაბილურობას event streaming-ისთვის, MinIO — Lakehouse-ის ფიზიკურ storage-ს, რომელსაც Flink წერს, Presto კითხულობს SQL-ით, Python — ML ანალიზისთვის. **Metabase** იძლევა BI დეშბორდს Presto-ს გავლით; ექსპერიმენტის სკრიპტი ზომავს end-to-end CDC latency-ს და იწერს KPI შედეგებს.
