-- Top 10 Products by Revenue
-- =================================================================
-- Classic best-sellers query joining the fact with dim_product.
-- =================================================================

SELECT
    dp.product_number,
    dp.product_name,
    dp.category_name,
    dp.subcategory_name,
    SUM(f.order_qty)                AS units_sold,
    ROUND(SUM(f.line_total), 2)     AS revenue,
    ROUND(AVG(f.unit_price), 2)     AS avg_unit_price
FROM iceberg.gold.fact_sales_order_line f
JOIN iceberg.gold.dim_product           dp
  ON dp.product_id = f.product_id
GROUP BY dp.product_number, dp.product_name,
         dp.category_name,  dp.subcategory_name
ORDER BY revenue DESC
LIMIT 10;
