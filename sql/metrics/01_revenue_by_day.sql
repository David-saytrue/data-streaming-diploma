-- Revenue by Day
-- =================================================================
-- Daily total revenue (line_total summed across the fact).
-- Demonstrates: fact ⨝ dim_date, basic aggregation, time series.
-- =================================================================

SELECT
    dd.full_date,
    dd.day_name,
    COUNT(DISTINCT f.sales_order_id)              AS orders,
    SUM(f.order_qty)                              AS units_sold,
    ROUND(SUM(f.line_total), 2)                   AS revenue,
    ROUND(SUM(f.discount_amount), 2)              AS discounts
FROM iceberg.gold.fact_sales_order_line f
JOIN iceberg.gold.dim_date              dd
  ON dd.full_date = CAST(f.order_ts AS DATE)
GROUP BY dd.full_date, dd.day_name
ORDER BY dd.full_date;
