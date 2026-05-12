-- Revenue by Month with Month-over-Month growth
-- =================================================================
-- Window function over months to compute MoM growth %.
-- Demonstrates: aggregation + LAG + analytical SQL on Lakehouse.
-- =================================================================

WITH monthly AS (
    SELECT
        dd.year_month,
        ROUND(SUM(f.line_total), 2) AS revenue
    FROM iceberg.gold.fact_sales_order_line f
    JOIN iceberg.gold.dim_date              dd
      ON dd.full_date = CAST(f.order_ts AS DATE)
    GROUP BY dd.year_month
)
SELECT
    year_month,
    revenue,
    LAG(revenue) OVER (ORDER BY year_month) AS prev_month_revenue,
    ROUND(
        100.0 * (revenue - LAG(revenue) OVER (ORDER BY year_month))
              / NULLIF(LAG(revenue) OVER (ORDER BY year_month), 0),
        2
    ) AS mom_growth_pct
FROM monthly
ORDER BY year_month;
