-- Discount Impact Analysis
-- =================================================================
-- Compares gross vs net revenue and computes effective discount %.
-- Also breaks down by customer segment, since wholesale buyers
-- typically receive higher discounts than retail.
-- =================================================================

SELECT
    dc.customer_segment,
    ROUND(SUM(f.gross_amount),    2)                          AS gross_revenue,
    ROUND(SUM(f.discount_amount), 2)                          AS total_discount,
    ROUND(SUM(f.line_total),      2)                          AS net_revenue,
    ROUND(100.0 * SUM(f.discount_amount)
                / NULLIF(SUM(f.gross_amount), 0), 2)          AS effective_discount_pct
FROM iceberg.gold.fact_sales_order_line f
JOIN iceberg.gold.dim_customer          dc
  ON dc.customer_id = f.customer_id
GROUP BY dc.customer_segment
ORDER BY net_revenue DESC;
