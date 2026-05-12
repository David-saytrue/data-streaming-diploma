# Analytical Metrics Pack

Reusable SQL queries against the **Gold star schema** in the Iceberg
lakehouse, intended to be executed from the PrestoDB CLI:

```powershell
docker exec -it data-streaming-diploma-presto-1 /opt/presto-cli
```

```sql
USE iceberg.gold;
-- then paste the contents of any file from this folder
```

| # | File | Demonstrates |
|---|------|--------------|
| 01 | `01_revenue_by_day.sql`          | Time-series revenue, fact ⨝ dim_date |
| 02 | `02_revenue_by_month.sql`        | Window functions (LAG) + MoM growth  |
| 03 | `03_top_products.sql`            | Top-N over dim_product hierarchy     |
| 04 | `04_aov_and_basket.sql`          | AOV, basket size                     |
| 05 | `05_sales_by_territory.sql`      | Geographic breakdown                 |
| 06 | `06_discount_impact.sql`         | Gross vs net, discount % per segment |
| 07 | `07_salesperson_performance.sql` | Quota attainment, commission         |
| 08 | `08_time_travel_demo.sql`        | Iceberg snapshots, FOR VERSION AS OF |

Before running these, populate the date dimension once:

```powershell
docker exec -i data-streaming-diploma-presto-1 /opt/presto-cli `
    -f /opt/presto-server/etc/sql/dim_date.sql
```
