-- Iceberg Time Travel demo
-- =================================================================
-- Show how Apache Iceberg lets us query historical states of the
-- same table without keeping backups.  This ties the CDC pipeline
-- directly to the thesis topic ("Lakehouse + versioned storage").
-- =================================================================

-- 1) List all snapshots ever created for the sales fact:
SELECT * FROM iceberg.gold."fact_sales_order_line$snapshots"
ORDER BY committed_at DESC;

-- 2) Pick a snapshot_id from the result above and run, e.g.:
--    SELECT * FROM iceberg.gold.fact_sales_order_line FOR VERSION AS OF <snapshot_id>;
--
-- Or query by timestamp:
--    SELECT * FROM iceberg.gold.fact_sales_order_line
--    FOR TIMESTAMP AS OF TIMESTAMP '2026-05-12 10:00:00';

-- 3) Total revenue *as of* the previous snapshot (parameterize as needed):
-- Replace <SNAPSHOT_ID> with a real snapshot id from query (1).
-- SELECT SUM(line_total) AS revenue_then
-- FROM iceberg.gold.fact_sales_order_line FOR VERSION AS OF <SNAPSHOT_ID>;

-- 4) See the audit history of a single row in Bronze (raw CDC):
SELECT *
FROM iceberg.bronze.br_sales_order_header
WHERE sales_order_id = 1
ORDER BY modified_ts DESC;
