# BI დეშბორდი — Metabase + Presto (Iceberg Gold)

## რატომ Metabase?

დიპლომში Presto უკვე იძლევა SQL ანალიტიკას CLI-დან. **Metabase** ამავე Lakehouse-ს აძლევს ვიზუალურ BI ფენას — დაცვაზე ჩანს, რომ streaming შედეგი არა მხოლოდ ცხრილია, არამედ დეშბორდიც.

```text
Flink → Iceberg Gold @ MinIO → Presto ← Metabase (http://localhost:3000)
```

## გაშვება

```powershell
docker compose up -d metabase
# ან სრული სტეკი:
docker compose up -d
.\scripts\setup-metabase.ps1
```

UI: **http://localhost:3000**

## Presto კავშირი (Database → Add)

| ველი | მნიშვნელობა |
|------|-------------|
| Database type | **Presto** |
| Display name | AdventureWorks Lakehouse |
| Host | `presto` (Docker ქსელიდან) |
| Port | `8080` |
| Catalog | `iceberg` |
| Schema | `gold` |
| SSL | გამორთული |

თუ Metabase-ს ჰოსტიდან უკავშირდები (არა container-იდან), Host = `localhost`, მაგრამ უმჯობესია Docker ქსელი (`presto`).

## რეკომენდებული დეშბორდი: „AdventureWorks Sales“

შექმენი **Dashboard** და დაამატე 4–5 **Native query** (SQL) კითხვა:

### 1. ჯამური KPI (Number / Scalar)

```sql
SELECT
  ROUND(SUM(line_total), 2) AS total_revenue,
  COUNT(DISTINCT sales_order_id) AS orders,
  COUNT(*) AS order_lines
FROM fact_sales_order_line
```

### 2. შემოსავალი დღეების მიხედვით (Line chart)

```sql
SELECT
  CAST(order_ts AS DATE) AS order_day,
  ROUND(SUM(line_total), 2) AS revenue,
  COUNT(DISTINCT sales_order_id) AS orders
FROM fact_sales_order_line
GROUP BY 1
ORDER BY 1
```

### 3. Top პროდუქტები (Bar)

```sql
SELECT
  dp.product_name,
  ROUND(SUM(f.line_total), 2) AS revenue
FROM fact_sales_order_line f
JOIN dim_product dp ON dp.product_id = f.product_id
GROUP BY dp.product_name
ORDER BY revenue DESC
LIMIT 10
```

### 4. ტერიტორიები (Bar / Pie)

```sql
SELECT
  dt.territory_name,
  ROUND(SUM(f.line_total), 2) AS revenue
FROM fact_sales_order_line f
JOIN dim_territory dt ON dt.territory_id = f.territory_id
GROUP BY dt.territory_name
ORDER BY revenue DESC
```

### 5. ბოლო შეკვეთები (Table) — CDC დემოსთვის

```sql
SELECT
  sales_order_id,
  order_ts,
  customer_id,
  product_id,
  order_qty,
  line_total
FROM fact_sales_order_line
ORDER BY order_ts DESC NULLS LAST
LIMIT 15
```

## კავშირი ექსპერიმენტთან

1. გაუშვი `.\scripts\run-experiment.ps1` — PostgreSQL-ში INSERT + latency გაზომვა.
2. Metabase-ში განაახლე „ბოლო შეკვეთები“ — ახალი `sales_order_id` უნდა გამოჩნდეს.
3. KPI ბარათები (revenue / orders) გაიზრდება.

დეტალური შედეგები იწერება: `docs/experiment-results/latest.md`

## დიპლომში ერთი წინადადება

> Metabase უზრუნველყოფს BI ვიზუალიზაციას Presto-ს მეშვეობით Iceberg Gold star schema-ზე; CDC pipeline-ის შემდეგ ანალიტიკოსი იგივე მონაცემს ხედავს დეშბორდზე CLI-ის გარეშე.
