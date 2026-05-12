-- Sales by Territory
-- =================================================================
-- Geographic distribution of revenue and unique customers.
-- =================================================================

SELECT
    dt.territory_group,
    dt.country_region,
    dt.territory_name,
    COUNT(DISTINCT f.customer_id)                AS unique_customers,
    COUNT(DISTINCT f.sales_order_id)             AS orders,
    ROUND(SUM(f.line_total), 2)                  AS revenue,
    ROUND(SUM(f.line_total)
          / NULLIF(COUNT(DISTINCT f.customer_id), 0), 2)  AS revenue_per_customer
FROM iceberg.gold.fact_sales_order_line f
JOIN iceberg.gold.dim_territory         dt
  ON dt.territory_id = f.territory_id
GROUP BY dt.territory_group, dt.country_region, dt.territory_name
ORDER BY revenue DESC;
