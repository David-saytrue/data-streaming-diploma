# 🚀 Real-Time CDC + Lakehouse Pipeline (AdventureWorks → Star Schema)

A diploma project implementing a production-grade **real-time CDC pipeline**
on top of a **Lakehouse** built from open-source components. Operational
changes in a PostgreSQL **AdventureWorks** database are captured as events,
processed by Apache Flink, and materialised into a **dimensional star
schema** stored as Apache Iceberg tables on MinIO. Analysts query the
result through PrestoDB.

## 🏗️ Architecture

```text
AdventureWorks (PostgreSQL)
        │  WAL (logical decoding)
        ▼
   Debezium (Kafka Connect)
        │  CDC events as JSON
        ▼
      Apache Kafka
        │
        ▼
   Apache Flink (SQL)
   ├── Bronze: raw CDC mirrors (1:1 with source)
   └── Gold:   star schema (facts + dimensions)
        │
        ▼
   Apache Iceberg @ MinIO   ← Lakehouse storage
        │
        ▼
       PrestoDB              ← BI / SQL analytics
```

### Components

| Component | Version | Role |
|-----------|---------|------|
| **PostgreSQL** | 15 | OLTP source — AdventureWorks subset (Sales / Production / Person) |
| **Debezium** | 2.4 | CDC connector reading the PostgreSQL WAL |
| **Apache Kafka** | (Debezium 2.4) | Event log — one topic per source table |
| **Apache Flink** | 1.17.2 | Streaming SQL engine (Bronze + Gold pipelines) |
| **Apache Iceberg** | 1.4.3 | Open table format with ACID and time travel |
| **MinIO** | latest | S3-compatible object storage for the lakehouse |
| **PrestoDB** | latest | Distributed SQL engine over the lakehouse |

## 📊 Data Flow

1. **PostgreSQL** stores a slimmed-down **AdventureWorks** model:
   `person`, `production`, `sales` schemas (~10 tables).
2. **Debezium** monitors the WAL via `pgoutput` and emits a CDC event
   stream per table to Kafka topics `aw.<schema>.<table>`.
3. **Apache Flink** consumes the streams in `debezium-json` format and
   runs a single multi-statement SQL job that maintains:
   - **Bronze** — exact mirrors of every source table in
     `iceberg.bronze.br_*` (audit + time travel substrate).
   - **Gold** — a dimensional **star schema** in `iceberg.gold.*`,
     built by streaming joins on primary keys.
4. **Apache Iceberg** manages snapshots, schema evolution and ACID
   commits; every Flink checkpoint produces a new snapshot.
5. **MinIO** stores the Parquet data files and Iceberg metadata.
6. **PrestoDB** reads the same files via the Hadoop Iceberg catalog.

## ⭐ Star Schema (Gold layer)

Single fact at the **order-line** grain, surrounded by conformed
dimensions:

```text
                          ┌──────────────────┐
                          │   dim_date       │
                          └────────┬─────────┘
                                   │
   ┌────────────┐   ┌──────────────┴─────────────┐   ┌────────────────┐
   │ dim_product├──►│  fact_sales_order_line     │◄──┤ dim_customer   │
   └────────────┘   │                            │   └────────────────┘
                    │   sales_order_id           │
   ┌────────────┐   │   sales_order_detail_id    │   ┌────────────────┐
   │dim_territory├─►│   order_qty / unit_price   │◄──┤ dim_salesperson│
   └────────────┘   │   line_total / discount    │   └────────────────┘
                    └──────────────┬─────────────┘
                                   │
                          ┌────────┴─────────┐
                          │  dim_currency    │
                          └──────────────────┘
```

| Layer | Iceberg location | What it is |
|-------|------------------|------------|
| Bronze | `iceberg.bronze.br_*`           | Raw CDC mirrors, one per source table |
| Gold   | `iceberg.gold.fact_sales_order_line` | The single business fact |
| Gold   | `iceberg.gold.dim_customer`     | customer ⨝ person ⨝ territory |
| Gold   | `iceberg.gold.dim_product`      | product ⨝ subcategory ⨝ category |
| Gold   | `iceberg.gold.dim_territory`    | sales territory |
| Gold   | `iceberg.gold.dim_salesperson`  | salesperson ⨝ person ⨝ territory |
| Gold   | `iceberg.gold.dim_currency`     | currency reference |
| Gold   | `iceberg.gold.dim_date`         | generated date dimension (one-shot in Presto) |

## 🗂️ Project Structure

```text
data-streaming-diploma/
├── docker-compose.yml             # All services configuration
├── flink_job.sql                  # Multi-statement Flink SQL pipeline
├── init.sql                       # AdventureWorks PostgreSQL subset
├── register-connector.json        # Debezium multi-table connector
├── flink/
│   ├── Dockerfile                 # Custom Flink image with S3/Iceberg JARs
│   └── core-site.xml              # Hadoop S3A configuration for Flink
├── presto/
│   └── catalog/
│       └── iceberg.properties     # Presto Iceberg/S3 catalog
└── sql/
    ├── dim_date.sql               # One-shot date-dimension generator
    └── metrics/                   # Analytical queries (BI / KPI pack)
        ├── 01_revenue_by_day.sql
        ├── 02_revenue_by_month.sql
        ├── 03_top_products.sql
        ├── 04_aov_and_basket.sql
        ├── 05_sales_by_territory.sql
        ├── 06_discount_impact.sql
        ├── 07_salesperson_performance.sql
        ├── 08_time_travel_demo.sql
        └── README.md
```

## 🚀 Quick Start

### Prerequisites
- Docker Desktop
- Docker Compose

### 1. Start all services
```powershell
docker-compose up -d
```

### 2. Register the Debezium connector
Wait 30–40 seconds for MinIO and Kafka to come up, then:

```powershell
$json = Get-Content register-connector.json -Raw
Invoke-RestMethod -Uri "http://localhost:8083/connectors" -Method Post -Body $json -ContentType "application/json"
```

Bash equivalent:

```bash
curl -X POST http://localhost:8083/connectors \
     -H "Content-Type: application/json" \
     -d @register-connector.json
```

### 3. Submit the Flink streaming pipeline
The full Bronze + Gold pipeline is shipped as a single SQL file:

```powershell
docker exec -it data-streaming-diploma-jobmanager-1 `
    /opt/flink/bin/sql-client.sh -f /opt/flink/flink_job.sql
```

A single Flink job named `adventureworks-cdc-lakehouse` should appear in
the dashboard at http://localhost:8081.

### 4. Generate `dim_date` (one-off)
```powershell
docker exec -i data-streaming-diploma-presto-1 `
    /opt/presto-cli --catalog iceberg --schema gold `
    -f /opt/presto-server/etc/sql/dim_date.sql
```

### 5. Test the CDC flow
Insert a new order in PostgreSQL and watch it propagate:

```powershell
docker exec -it data-streaming-diploma-postgres-1 `
    psql -U postgres -d adventureworks -c `
    "INSERT INTO sales.sales_order_header
        (customer_id, sales_person_id, territory_id, currency_code,
         sub_total, tax_amt, freight, total_due)
     VALUES (1, 1, 1, 'GEL', 79.99, 7.99, 5.00, 92.98);"
```

Wait ~10 s for a Flink checkpoint, then query the lakehouse:

### 6. Query the lakehouse with PrestoDB
```powershell
docker exec -it data-streaming-diploma-presto-1 /opt/presto-cli
```
```sql
USE iceberg.gold;
SELECT * FROM fact_sales_order_line ORDER BY order_ts DESC LIMIT 10;
SELECT * FROM dim_customer;
```

### 7. Run the analytics pack
Every file in `sql/metrics/` is a self-contained Presto query.
For example, top products by revenue:

```powershell
Get-Content sql/metrics/03_top_products.sql | `
    docker exec -i data-streaming-diploma-presto-1 /opt/presto-cli
```

## 🌐 Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| **Flink Dashboard** | http://localhost:8081 | — |
| **MinIO Console**   | http://localhost:9001 | admin / adminpassword |
| **Kafka Connect**   | http://localhost:8083 | — |
| **PrestoDB**        | http://localhost:8080 | — |

## 🏛️ Lakehouse highlights demonstrated

- ✅ **Medallion architecture** — Bronze (raw CDC) + Gold (star schema)
- ✅ **Streaming dimensional modelling** — fact and dims maintained
  with Flink SQL streaming joins on primary keys
- ✅ **Iceberg format-version 2** — row-level deletes & upserts
- ✅ **Snapshot isolation** — every Flink checkpoint commits an
  atomic Iceberg snapshot
- ✅ **Time travel** — query the star schema *as of* any past
  snapshot without restoring a backup (see `sql/metrics/08_time_travel_demo.sql`)
- ✅ **Open interoperability** — Flink writes, Presto reads, both
  against the same Parquet files via the open Iceberg spec
