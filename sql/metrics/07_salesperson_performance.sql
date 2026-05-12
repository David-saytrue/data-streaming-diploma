-- Salesperson Performance vs Quota
-- =================================================================
-- Each salesperson is measured against their personal sales_quota
-- stored in dim_salesperson.
-- =================================================================

SELECT
    dsp.full_name,
    dsp.territory_name,
    dsp.sales_quota,
    COUNT(DISTINCT f.sales_order_id)                       AS orders,
    ROUND(SUM(f.line_total), 2)                            AS revenue_generated,
    ROUND(100.0 * SUM(f.line_total)
                / NULLIF(dsp.sales_quota, 0), 2)           AS quota_attainment_pct,
    ROUND(SUM(f.line_total) * dsp.commission_pct, 2)       AS estimated_commission
FROM iceberg.gold.fact_sales_order_line f
JOIN iceberg.gold.dim_salesperson       dsp
  ON dsp.sales_person_id = f.sales_person_id
GROUP BY dsp.full_name, dsp.territory_name,
         dsp.sales_quota, dsp.commission_pct
ORDER BY revenue_generated DESC;
