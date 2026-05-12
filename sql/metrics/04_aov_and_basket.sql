-- Average Order Value & Basket Size
-- =================================================================
-- AOV  = total revenue / number of distinct orders
-- ABS  = total units   / number of distinct orders
-- =================================================================

SELECT
    COUNT(DISTINCT f.sales_order_id)                                AS orders,
    SUM(f.order_qty)                                                AS units,
    ROUND(SUM(f.line_total), 2)                                     AS total_revenue,
    ROUND(SUM(f.line_total)
          / NULLIF(COUNT(DISTINCT f.sales_order_id), 0), 2)         AS aov,
    ROUND(CAST(SUM(f.order_qty) AS DOUBLE)
          / NULLIF(COUNT(DISTINCT f.sales_order_id), 0), 2)         AS avg_basket_size
FROM iceberg.gold.fact_sales_order_line f;
