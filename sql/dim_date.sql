-- =====================================================================
-- dim_date — generated date dimension for the AdventureWorks star schema
-- =====================================================================
-- Run once via the PrestoDB CLI:
--
--     docker exec -i data-streaming-diploma-presto-1 \
--         /opt/presto-cli --catalog iceberg --schema gold \
--         -f /opt/presto-server/etc/sql/dim_date.sql
--
-- Generates ~7 years of dates (2024-01-01 through 2030-12-31), enough
-- to comfortably cover every order in the source AdventureWorks data
-- plus future demos.  Re-running the script is safe — it drops and
-- recreates the table.
-- =====================================================================

DROP TABLE IF EXISTS iceberg.gold.dim_date;

CREATE TABLE iceberg.gold.dim_date AS
WITH date_series AS (
    SELECT date_add('day', s.n, DATE '2024-01-01') AS d
    FROM UNNEST(SEQUENCE(0, 365 * 7 + 1)) AS s (n)
)
SELECT
    CAST(date_format(d, '%Y%m%d') AS INTEGER)            AS date_key,
    d                                                    AS full_date,
    year(d)                                              AS year,
    quarter(d)                                           AS quarter,
    month(d)                                             AS month,
    date_format(d, '%M')                                 AS month_name,
    day_of_month(d)                                      AS day_of_month,
    day_of_week(d)                                       AS day_of_week,  -- 1=Mon … 7=Sun
    date_format(d, '%W')                                 AS day_name,
    week(d)                                              AS iso_week,
    day_of_year(d)                                       AS day_of_year,
    CAST(year(d) AS VARCHAR) || '-Q'
        || CAST(quarter(d) AS VARCHAR)                   AS year_quarter,
    date_format(d, '%Y-%m')                              AS year_month,
    CASE WHEN day_of_week(d) IN (6, 7) THEN TRUE
         ELSE FALSE END                                  AS is_weekend
FROM date_series;
