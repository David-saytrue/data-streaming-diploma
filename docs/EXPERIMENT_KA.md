# ექსპერიმენტი — CDC Latency და ანალიტიკური შედეგები

## მიზანი

გავზომოთ, რამდენ ხანში ჩანს PostgreSQL-ში გაკეთებული ცვლილება Lakehouse **Gold** ფენაში, და დავაფიქსიროთ KPI + (სურვილისამებრ) K-Means შედეგები დაცვისთვის.

## რა სკრიპტი აკეთებს ცვლილებას?

უკვე გაქვს **`demo-pipeline.ps1`** — ის აკეთებს:

1. PostgreSQL-ში `INSERT` (1 order header + 1 line)
2. Kafka-ში CDC event-ის ჩვენებას
3. Bronze / Gold-ის შემოწმებას Presto-თი

ახალი სკრიპტი **`scripts/run-experiment.ps1`** იმავე INSERT-ს იყენებს, მაგრამ დამატებით:

| ნაბიჯი | რას აკეთებს |
|--------|-------------|
| BEFORE | ითვლის Gold row-ებს |
| INSERT | იგივე SQL რაც `demo-pipeline.ps1`-ში |
| POLL | ყოველ 3 წამში ამოწმებს Presto-ში ახალ `sales_order_id`-ს |
| LATENCY | იწერს წამებს INSERT-დან Gold-ში გამოჩენამდე |
| KPI | revenue, top products, territory |
| ML | K-Means (შეგიძლია `-SkipKMeans`) |
| REPORT | წერს `docs/experiment-results/latest.md` |

```text
demo-pipeline.ps1     = სრული CDC დემო (Kafka dump + Bronze/Gold preview)
run-experiment.ps1    = გაზომვადი ექსპერიმენტი + ანგარიში დაცვისთვის
```

## გაშვების რიგი

```powershell
# 1. ინფრა + Flink (თუ ჯერ არ გაქვს გაშვებული)
docker compose up -d
.\demo-pipeline.ps1          # პირველად სრული; ან -SkipInfra თუ უკვე მუშაობს

# 2. ექსპერიმენტი (ახალი INSERT + latency)
.\scripts\run-experiment.ps1

# 3. BI
.\scripts\setup-metabase.ps1
# გახსენი http://localhost:3000 — იხ. docs/BI_DASHBOARD_KA.md
```

მხოლოდ latency, ML-ის გარეშე:

```powershell
.\scripts\run-experiment.ps1 -SkipKMeans
```

## მოსალოდნელი შედეგი

| მეტრიკა | ტიპიური მნიშვნელობა (ლოკალური Docker) |
|---------|----------------------------------------|
| End-to-end latency | **~10–40 წამი** (Flink checkpoint = 10s) |
| ახალი ხაზი Gold-ში | `product_id=11`, `order_qty=2`, `line_total≈19.98` |
| KPI | orders/revenue იზრდება 1 შეკვეთით |

თუ **TIMEOUT**: შეამოწმე Flink UI http://localhost:8081 — job უნდა იყოს **RUNNING**.

## ანგარიშის ფაილები

- `docs/experiment-results/latest.md` — ბოლო გაშვება
- `docs/experiment-results/run_YYYYMMDD_HHMMSS.md` — ისტორია

პირველ გაშვებამდე `latest.md` შეიძლება არ არსებობდეს — სკრიპტი თავად შექმნის.

## დიპლომში დასკვნის შაბლონი

> ექსპერიმენტში PostgreSQL AdventureWorks ბაზაში ახალი შეკვეთის ჩაწერის შემდეგ CDC pipeline-მა (Debezium → Kafka → Flink → Iceberg) მონაცემი Gold ფენაში **X წამში** გამოაჩინა. იგივე მონაცემი ხელმისაწვდომია Presto SQL-ით და Metabase დეშბორდზე; batch ფენაზე Airflow-ით გაშვებული K-Means კლიენტებს სეგმენტირებს შეძენის ქცევის მიხედვით.
