# === CDC LATENCY EXPERIMENT + REPORT ===

**Run:** 2026-07-17 12:46:08  
**Script:** `scripts/run-experiment.ps1`  
**Path:** PostgreSQL INSERT -> Debezium -> Kafka -> Flink -> Iceberg Gold -> Presto

---

## 1. End-to-end latency

```
=== CDC LATENCY EXPERIMENT ===
PostgreSQL INSERT -> Debezium -> Kafka -> Flink -> Iceberg Gold -> Presto

[BEFORE] Gold fact rows: 17
[BEFORE] Max sales_order_id in Gold: 10

[INSERT] New sales_order_id: 11
[OK]     Visible in Gold after 14.4s

[AFTER]  Gold fact rows: 18
[AFTER]  New Gold row: "11","1","11","2","19.980000"

Latency: 14.4s | order_id=11 | Gold 17 -> 18
Timeout: 120s | Poll interval: 3s
```

**Interpretation:** latency includes Debezium WAL read, Kafka publish, Flink checkpoint (~10s), and Iceberg commit on MinIO. Typical local demo range: **~10-40 seconds**.

---

## 2. KPI snapshot (Presto / Gold)

```
[KPI] Running analytics pack samples...

Total revenue / lines:
"22148.600000","18","18"

Top 5 products by revenue:
"Mountain-100 Black","6799.980000"
"Mountain-200 Silver","4399.980000"
"Road-150 Red","3578.270000"
"Road-250 Black","2443.400000"
"Touring-1000 Blue","2384.070000"

Revenue by territory:
"Batumi","6021.670000"
"Tbilisi","5639.940000"
"Paris","3479.980000"
"Berlin","2897.250000"
"New York","2384.070000"
```

Same metrics as the Metabase dashboard (see `docs/BI_DASHBOARD_KA.md`).

---

## 3. K-Means (batch ML)

```
[ML] K-Means: _skipped_
```

Output files in MinIO: `lakehouse-admin/analytics/customer_clusters/`

---

## 4. Short thesis conclusion

1. An OLTP change in PostgreSQL appears automatically in the Lakehouse Gold layer via the CDC pipeline.
2. Measured end-to-end latency: **14.4 seconds**.
3. The same data is available for KPI analytics via Presto/Metabase after the stream catches up.
4. Airflow + K-Means demonstrates a batch ML layer separate from streaming.

---

```
Report written:
  docs/experiment-results/run_20260717_124608.md
  docs/experiment-results/latest.md

Latency: 14.4s | order_id=11 | Gold 17 -> 18
Metabase: http://localhost:3000  |  setup: .\scripts\setup-metabase.ps1
```
