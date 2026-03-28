# 🚀 Real-Time Data Streaming Pipeline

A diploma project implementing a production-grade **real-time data streaming pipeline** using modern open-source Data Engineering tools. The system captures database changes in real-time and stores them in a Data Lake using the **Lakehouse architecture**.

## 🏗️ Architecture

```text
PostgreSQL → Debezium (CDC) → Apache Kafka → Apache Flink → Apache Iceberg (MinIO) → PrestoDB
```

### Components

| Component | Version | Role |
|-----------|---------|------|
| **PostgreSQL** | 14 | Source operational database (`shop.orders` table) |
| **Debezium** | 2.4 | Change Data Capture (CDC) — reads PostgreSQL WAL log |
| **Apache Kafka** | (Debezium 2.4) | Message broker — topic `shop.shop.orders` |
| **Apache ZooKeeper** | (Debezium 2.4) | Kafka coordination service |
| **Apache Flink** | 1.17.2 | Stream processing engine — SQL-based ETL |
| **Apache Iceberg** | 1.4.3 | Open table format with ACID transactions |
| **MinIO** | latest | S3-compatible object storage (Data Lake) |
| **PrestoDB** | latest | Serving layer for interactive SQL analytics over the Data Lakehouse |

## 📊 Data Flow

1. **PostgreSQL** stores e-commerce orders in the `shop.orders` table
2. **Debezium** monitors the PostgreSQL WAL (Write-Ahead Log) and captures every INSERT, UPDATE, DELETE as a CDC event
3. **Apache Kafka** receives the CDC events as JSON messages in the `shop.shop.orders` topic
4. **Apache Flink** consumes the Kafka stream using `debezium-json` format and writes the data to an Iceberg table via a streaming SQL job with 10-second checkpointing
5. **Apache Iceberg** manages the table metadata (snapshots, manifests) and provides ACID transactions with upsert support (format-version 2)
6. **MinIO** stores the Iceberg data files (`.parquet`) and metadata (`.json`, `.avro`) in the `lakehouse-admin` bucket
7. **PrestoDB** connects to MinIO using the Hadoop Iceberg Catalog to provide fast distributed SQL querying over the data lake files.

## 🗂️ Project Structure

```text
data-streaming-diploma/
├── docker-compose.yml          # All services configuration
├── flink_job.sql               # Flink SQL streaming job
├── init.sql                    # PostgreSQL schema & seed data
├── register-connector.json     # Debezium connector config template
├── flink/
│   ├── Dockerfile              # Custom Flink image with S3/Iceberg JARs
│   └── core-site.xml           # Hadoop S3A configuration for Flink
└── presto/
    └── catalog/
        └── iceberg.properties  # Presto Iceberg S3 catalog configuration
```

## ⚙️ How It Works

### Flink SQL Job (`flink_job.sql`)
- Creates an **Iceberg catalog** backed by MinIO (S3A protocol)
- Defines a **Kafka source table** (`kafka_orders`) in the default catalog using `debezium-json` format
- Defines an **Iceberg sink table** (`iceberg_orders`) with upsert mode enabled
- Runs a continuous `INSERT INTO ... SELECT * FROM ...` streaming job
- Checkpointing every **10 seconds** to commit Iceberg snapshots to MinIO

## 🚀 Quick Start

### Prerequisites
- Docker Desktop
- Docker Compose

### 1. Start all services
```powershell
docker-compose up -d
```

### 2. Register the Debezium connector
Wait for 30-40 seconds for all services (especially MinIO and Kafka) to fully start, then run:

*For PowerShell:*
```powershell
$json = Get-Content register-connector.json -Raw
Invoke-RestMethod -Uri "http://localhost:8083/connectors" -Method Post -Body $json -ContentType "application/json"
```

*For Bash/Linux:*
```bash
curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d @register-connector.json
```

### 3. Start the Flink streaming job
Submit the continuous ETL streaming job to Flink:
```powershell
docker exec -it data-streaming-diploma-jobmanager-1 /opt/flink/bin/sql-client.sh -f /opt/flink/flink_job.sql
```

### 4. Insert test data & Verify CDC
Test the Change Data Capture flow by making a change in PostgreSQL:
```powershell
docker exec -it data-streaming-diploma-postgres-1 psql -U postgres -d shop_db -c "INSERT INTO shop.orders (customer_name, product_id, price) VALUES ('Alex Tesla', 555, 77700.00);"
```
*(Wait 10 seconds for the Flink checkpoint to commit the changes to MinIO)*

### 5. Query the Data Lake using PrestoDB 
Hop into the interactive Presto query console to analyze your Iceberg tables:
```powershell
docker exec -it data-streaming-diploma-presto-1 /opt/presto-cli
```
Execute your query:
```sql
USE iceberg.shop_analytics;
SELECT * FROM iceberg_orders;
```

## 🌐 Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| **Flink Dashboard** | http://localhost:8081 | — |
| **MinIO Console** | http://localhost:9001 | admin / adminpassword |
| **Kafka Connect (Debezium)** | http://localhost:8083 | — |
| **PrestoDB Console** | http://localhost:8080 | — |

## 🏛️ Lakehouse Architecture Highlights

This project implements the **Lakehouse pattern** — combining the scalability and cost-efficiency of a Data Lake with the ACID transactions and schema enforcement of a Data Warehouse.

Key features successfully demonstrated in this diploma:
- ✅ **Format version 2** — enables row-level deletes and upserts
- ✅ **UPSERT mode** — handles CDC UPDATE/DELETE operations correctly
- ✅ **Snapshot isolation** — every Flink checkpoint creates an atomic Iceberg snapshot
- ✅ **Interoperability** — Flink processes the real-time streams, while Presto simultaneously queries the exact same Parquet data files using open table formats.
