-- =====================================================================
-- AdventureWorks → Lakehouse streaming pipeline (Flink SQL)
-- =====================================================================
-- This single Flink SQL script implements an end-to-end CDC pipeline
-- built around a Medallion architecture:
--
--   Kafka (Debezium)  →  Bronze (Iceberg)   raw CDC mirrors, audit log
--                     →  Gold   (Iceberg)   star schema for analytics
--
-- All streaming inserts are submitted as one Flink job via
-- EXECUTE STATEMENT SET, so checkpoints commit atomically across the
-- whole lakehouse.
--
-- Conventions:
--   • Decimals arrive as STRING (Debezium decimal.handling.mode=string)
--     and are CAST to DECIMAL on the way into Iceberg.
--   • Postgres TIMESTAMP arrives as BIGINT microseconds since epoch
--     and is converted to TIMESTAMP(3) via TO_TIMESTAMP_LTZ(us/1000, 3).
--     (Flink 1.17 only accepts precision 0 and 3.)
--   • Postgres DATE arrives as INT days since epoch and is converted
--     with TO_DATE(FROM_UNIXTIME(... * 86400)).
--   • All Iceberg tables use format-version 2 + write.upsert.enabled
--     so CDC upserts and deletes are handled correctly.
-- =====================================================================

-- =====================================================================
-- 0.  Engine configuration
-- =====================================================================
SET 'execution.checkpointing.interval' = '10s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'pipeline.name' = 'adventureworks-cdc-lakehouse';

-- =====================================================================
-- 1.  Iceberg catalog and lakehouse namespaces
-- =====================================================================
CREATE CATALOG iceberg_catalog WITH (
    'type'           = 'iceberg',
    'catalog-type'   = 'hadoop',
    'warehouse'      = 's3a://lakehouse-admin/iceberg_data'
);

CREATE DATABASE IF NOT EXISTS iceberg_catalog.bronze;
CREATE DATABASE IF NOT EXISTS iceberg_catalog.gold;

-- =====================================================================
-- 2.  Kafka source tables (default catalog, in-memory)
--     One CREATE TABLE per AdventureWorks source table.  All declared
--     as upsert sources via PRIMARY KEY + debezium-json format.
-- =====================================================================
USE CATALOG default_catalog;
USE default_database;

-- person.person
CREATE TABLE IF NOT EXISTS kafka_person (
    business_entity_id INT,
    person_type        STRING,
    first_name         STRING,
    last_name          STRING,
    email_address      STRING,
    modified_date      BIGINT,
    PRIMARY KEY (business_entity_id) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.person.person',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-person',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- production.product_category
CREATE TABLE IF NOT EXISTS kafka_product_category (
    product_category_id INT,
    name                STRING,
    modified_date       BIGINT,
    PRIMARY KEY (product_category_id) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.production.product_category',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-product_category',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- production.product_subcategory
CREATE TABLE IF NOT EXISTS kafka_product_subcategory (
    product_subcategory_id INT,
    product_category_id    INT,
    name                   STRING,
    modified_date          BIGINT,
    PRIMARY KEY (product_subcategory_id) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.production.product_subcategory',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-product_subcategory',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- production.product
CREATE TABLE IF NOT EXISTS kafka_product (
    product_id             INT,
    product_subcategory_id INT,
    name                   STRING,
    product_number         STRING,
    color                  STRING,
    standard_cost          STRING,   -- DECIMAL serialized as string
    list_price             STRING,
    size                   STRING,
    weight                 STRING,
    sell_start_date        INT,      -- days since epoch
    sell_end_date          INT,
    modified_date          BIGINT,
    PRIMARY KEY (product_id) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.production.product',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-product',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- sales.sales_territory
CREATE TABLE IF NOT EXISTS kafka_sales_territory (
    territory_id   INT,
    name           STRING,
    country_region STRING,
    `group`        STRING,
    modified_date  BIGINT,
    PRIMARY KEY (territory_id) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.sales.sales_territory',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-sales_territory',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- sales.currency
CREATE TABLE IF NOT EXISTS kafka_currency (
    currency_code STRING,
    name          STRING,
    modified_date BIGINT,
    PRIMARY KEY (currency_code) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.sales.currency',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-currency',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- sales.customer
CREATE TABLE IF NOT EXISTS kafka_customer (
    customer_id      INT,
    person_id        INT,
    territory_id     INT,
    account_number   STRING,
    customer_segment STRING,
    modified_date    BIGINT,
    PRIMARY KEY (customer_id) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.sales.customer',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-customer',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- sales.sales_person
CREATE TABLE IF NOT EXISTS kafka_sales_person (
    business_entity_id INT,
    territory_id       INT,
    sales_quota        STRING,
    commission_pct     STRING,
    modified_date      BIGINT,
    PRIMARY KEY (business_entity_id) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.sales.sales_person',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-sales_person',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- sales.sales_order_header
CREATE TABLE IF NOT EXISTS kafka_sales_order_header (
    sales_order_id   INT,
    order_date       BIGINT,
    ship_date        BIGINT,
    status           SMALLINT,
    customer_id      INT,
    sales_person_id  INT,
    territory_id     INT,
    currency_code    STRING,
    sub_total        STRING,
    tax_amt          STRING,
    freight          STRING,
    total_due        STRING,
    modified_date    BIGINT,
    PRIMARY KEY (sales_order_id) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.sales.sales_order_header',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-sales_order_header',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- sales.sales_order_detail
CREATE TABLE IF NOT EXISTS kafka_sales_order_detail (
    sales_order_id        INT,
    sales_order_detail_id INT,
    product_id            INT,
    order_qty             SMALLINT,
    unit_price            STRING,
    unit_price_discount   STRING,
    line_total            STRING,
    modified_date         BIGINT,
    PRIMARY KEY (sales_order_id, sales_order_detail_id) NOT ENFORCED
) WITH (
    'connector'                          = 'kafka',
    'topic'                              = 'aw.sales.sales_order_detail',
    'properties.bootstrap.servers'       = 'kafka:9092',
    'properties.group.id'                = 'flink-aw-sales_order_detail',
    'scan.startup.mode'                  = 'earliest-offset',
    'format'                             = 'debezium-json',
    'debezium-json.schema-include'       = 'true',
    'debezium-json.ignore-parse-errors'  = 'true'
);

-- =====================================================================
-- 3.  Bronze layer — raw CDC mirrors in Iceberg
--     1:1 with the operational tables.  Used as the auditable
--     "raw data lake" and the source for Iceberg time-travel demos.
-- =====================================================================
CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_person (
    business_entity_id INT,
    person_type        STRING,
    first_name         STRING,
    last_name          STRING,
    email_address      STRING,
    modified_ts        TIMESTAMP_LTZ(3),
    PRIMARY KEY (business_entity_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_product_category (
    product_category_id INT,
    name                STRING,
    modified_ts         TIMESTAMP_LTZ(3),
    PRIMARY KEY (product_category_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_product_subcategory (
    product_subcategory_id INT,
    product_category_id    INT,
    name                   STRING,
    modified_ts            TIMESTAMP_LTZ(3),
    PRIMARY KEY (product_subcategory_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_product (
    product_id             INT,
    product_subcategory_id INT,
    name                   STRING,
    product_number         STRING,
    color                  STRING,
    standard_cost          DECIMAL(12, 4),
    list_price             DECIMAL(12, 4),
    size                   STRING,
    weight                 DECIMAL(8, 2),
    sell_start_date        DATE,
    sell_end_date          DATE,
    modified_ts            TIMESTAMP_LTZ(3),
    PRIMARY KEY (product_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_sales_territory (
    territory_id   INT,
    name           STRING,
    country_region STRING,
    territory_group STRING,
    modified_ts    TIMESTAMP_LTZ(3),
    PRIMARY KEY (territory_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_currency (
    currency_code STRING,
    name          STRING,
    modified_ts   TIMESTAMP_LTZ(3),
    PRIMARY KEY (currency_code) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_customer (
    customer_id      INT,
    person_id        INT,
    territory_id     INT,
    account_number   STRING,
    customer_segment STRING,
    modified_ts      TIMESTAMP_LTZ(3),
    PRIMARY KEY (customer_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_sales_person (
    business_entity_id INT,
    territory_id       INT,
    sales_quota        DECIMAL(12, 2),
    commission_pct     DECIMAL(5, 4),
    modified_ts        TIMESTAMP_LTZ(3),
    PRIMARY KEY (business_entity_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_sales_order_header (
    sales_order_id   INT,
    order_ts         TIMESTAMP_LTZ(3),
    ship_ts          TIMESTAMP_LTZ(3),
    status           SMALLINT,
    customer_id      INT,
    sales_person_id  INT,
    territory_id     INT,
    currency_code    STRING,
    sub_total        DECIMAL(14, 4),
    tax_amt          DECIMAL(14, 4),
    freight          DECIMAL(14, 4),
    total_due        DECIMAL(14, 4),
    modified_ts      TIMESTAMP_LTZ(3),
    PRIMARY KEY (sales_order_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

CREATE TABLE IF NOT EXISTS iceberg_catalog.bronze.br_sales_order_detail (
    sales_order_id        INT,
    sales_order_detail_id INT,
    product_id            INT,
    order_qty             SMALLINT,
    unit_price            DECIMAL(12, 4),
    unit_price_discount   DECIMAL(5, 4),
    line_total            DECIMAL(20, 6),
    modified_ts           TIMESTAMP_LTZ(3),
    PRIMARY KEY (sales_order_id, sales_order_detail_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

-- =====================================================================
-- 4.  Gold layer — star schema dimensions
--     Conformed dimensions for the sales fact table.  Natural keys are
--     used as primary keys in this MVP; replacing them with hashed
--     surrogate keys + SCD2 is documented as a future iteration.
-- =====================================================================

-- dim_customer  = customer ⨝ person ⨝ territory  (denormalized)
CREATE TABLE IF NOT EXISTS iceberg_catalog.gold.dim_customer (
    customer_id       INT,
    account_number    STRING,
    full_name         STRING,
    email_address     STRING,
    customer_segment  STRING,
    territory_id      INT,
    territory_name    STRING,
    territory_group   STRING,
    country_region    STRING,
    PRIMARY KEY (customer_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

-- dim_product = product ⨝ subcategory ⨝ category
CREATE TABLE IF NOT EXISTS iceberg_catalog.gold.dim_product (
    product_id      INT,
    product_number  STRING,
    product_name    STRING,
    color           STRING,
    size            STRING,
    standard_cost   DECIMAL(12, 4),
    list_price      DECIMAL(12, 4),
    subcategory_id  INT,
    subcategory_name STRING,
    category_id     INT,
    category_name   STRING,
    PRIMARY KEY (product_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

-- dim_territory
CREATE TABLE IF NOT EXISTS iceberg_catalog.gold.dim_territory (
    territory_id    INT,
    territory_name  STRING,
    country_region  STRING,
    territory_group STRING,
    PRIMARY KEY (territory_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

-- dim_salesperson = sales_person ⨝ person ⨝ territory
CREATE TABLE IF NOT EXISTS iceberg_catalog.gold.dim_salesperson (
    sales_person_id  INT,
    full_name        STRING,
    email_address    STRING,
    territory_id     INT,
    territory_name   STRING,
    sales_quota      DECIMAL(12, 2),
    commission_pct   DECIMAL(5, 4),
    PRIMARY KEY (sales_person_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

-- dim_currency
CREATE TABLE IF NOT EXISTS iceberg_catalog.gold.dim_currency (
    currency_code STRING,
    currency_name STRING,
    PRIMARY KEY (currency_code) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

-- =====================================================================
-- 5.  Gold layer — sales fact (grain: one row per order line)
-- =====================================================================
CREATE TABLE IF NOT EXISTS iceberg_catalog.gold.fact_sales_order_line (
    sales_order_id        INT,
    sales_order_detail_id INT,
    order_ts              TIMESTAMP_LTZ(3),
    order_date            DATE,
    customer_id           INT,
    product_id            INT,
    territory_id          INT,
    sales_person_id       INT,
    currency_code         STRING,
    order_status          SMALLINT,
    order_qty             SMALLINT,
    unit_price            DECIMAL(12, 4),
    unit_price_discount   DECIMAL(5, 4),
    gross_amount          DECIMAL(20, 6),  -- order_qty * unit_price
    discount_amount       DECIMAL(20, 6),  -- gross * discount_pct
    line_total            DECIMAL(20, 6),  -- gross - discount
    PRIMARY KEY (sales_order_id, sales_order_detail_id) NOT ENFORCED
) WITH ('format-version' = '2', 'write.upsert.enabled' = 'true');

-- =====================================================================
-- 6.  Streaming pipeline — submit all INSERTs as a single Flink job
-- =====================================================================
EXECUTE STATEMENT SET
BEGIN
    ----------------------------------------------------------------
    -- 6.1  Bronze: 1:1 CDC mirrors
    ----------------------------------------------------------------
    INSERT INTO iceberg_catalog.bronze.br_person
    SELECT
        business_entity_id,
        person_type,
        first_name,
        last_name,
        email_address,
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_person;

    INSERT INTO iceberg_catalog.bronze.br_product_category
    SELECT
        product_category_id,
        name,
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_product_category;

    INSERT INTO iceberg_catalog.bronze.br_product_subcategory
    SELECT
        product_subcategory_id,
        product_category_id,
        name,
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_product_subcategory;

    INSERT INTO iceberg_catalog.bronze.br_product
    SELECT
        product_id,
        product_subcategory_id,
        name,
        product_number,
        color,
        CAST(standard_cost AS DECIMAL(12, 4)),
        CAST(list_price    AS DECIMAL(12, 4)),
        size,
        CAST(weight        AS DECIMAL(8, 2)),
        TO_DATE(FROM_UNIXTIME(CAST(sell_start_date AS BIGINT) * 86400)),
        TO_DATE(FROM_UNIXTIME(CAST(sell_end_date   AS BIGINT) * 86400)),
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_product;

    INSERT INTO iceberg_catalog.bronze.br_sales_territory
    SELECT
        territory_id,
        name,
        country_region,
        `group`,
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_sales_territory;

    INSERT INTO iceberg_catalog.bronze.br_currency
    SELECT
        currency_code,
        name,
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_currency;

    INSERT INTO iceberg_catalog.bronze.br_customer
    SELECT
        customer_id,
        person_id,
        territory_id,
        account_number,
        customer_segment,
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_customer;

    INSERT INTO iceberg_catalog.bronze.br_sales_person
    SELECT
        business_entity_id,
        territory_id,
        CAST(sales_quota    AS DECIMAL(12, 2)),
        CAST(commission_pct AS DECIMAL(5, 4)),
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_sales_person;

    INSERT INTO iceberg_catalog.bronze.br_sales_order_header
    SELECT
        sales_order_id,
        TO_TIMESTAMP_LTZ(order_date / 1000, 3),
        TO_TIMESTAMP_LTZ(ship_date  / 1000, 3),
        status,
        customer_id,
        sales_person_id,
        territory_id,
        currency_code,
        CAST(sub_total AS DECIMAL(14, 4)),
        CAST(tax_amt   AS DECIMAL(14, 4)),
        CAST(freight   AS DECIMAL(14, 4)),
        CAST(total_due AS DECIMAL(14, 4)),
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_sales_order_header;

    INSERT INTO iceberg_catalog.bronze.br_sales_order_detail
    SELECT
        sales_order_id,
        sales_order_detail_id,
        product_id,
        order_qty,
        CAST(unit_price          AS DECIMAL(12, 4)),
        CAST(unit_price_discount AS DECIMAL(5, 4)),
        CAST(line_total          AS DECIMAL(20, 6)),
        TO_TIMESTAMP_LTZ(modified_date / 1000, 3)
    FROM kafka_sales_order_detail;

    ----------------------------------------------------------------
    -- 6.2  Gold: conformed dimensions (built directly from Kafka
    --      streams via streaming joins on primary keys)
    ----------------------------------------------------------------
    INSERT INTO iceberg_catalog.gold.dim_customer
    SELECT
        c.customer_id,
        c.account_number,
        p.first_name || ' ' || p.last_name AS full_name,
        p.email_address,
        c.customer_segment,
        c.territory_id,
        t.name           AS territory_name,
        t.`group`        AS territory_group,
        t.country_region
    FROM kafka_customer c
    LEFT JOIN kafka_person          p ON p.business_entity_id = c.person_id
    LEFT JOIN kafka_sales_territory t ON t.territory_id       = c.territory_id;

    INSERT INTO iceberg_catalog.gold.dim_product
    SELECT
        p.product_id,
        p.product_number,
        p.name                              AS product_name,
        p.color,
        p.size,
        CAST(p.standard_cost AS DECIMAL(12, 4)),
        CAST(p.list_price    AS DECIMAL(12, 4)),
        p.product_subcategory_id            AS subcategory_id,
        sc.name                             AS subcategory_name,
        sc.product_category_id              AS category_id,
        cat.name                            AS category_name
    FROM kafka_product p
    LEFT JOIN kafka_product_subcategory sc  ON sc.product_subcategory_id = p.product_subcategory_id
    LEFT JOIN kafka_product_category    cat ON cat.product_category_id   = sc.product_category_id;

    INSERT INTO iceberg_catalog.gold.dim_territory
    SELECT
        territory_id,
        name           AS territory_name,
        country_region,
        `group`        AS territory_group
    FROM kafka_sales_territory;

    INSERT INTO iceberg_catalog.gold.dim_salesperson
    SELECT
        sp.business_entity_id              AS sales_person_id,
        p.first_name || ' ' || p.last_name AS full_name,
        p.email_address,
        sp.territory_id,
        t.name                             AS territory_name,
        CAST(sp.sales_quota    AS DECIMAL(12, 2)),
        CAST(sp.commission_pct AS DECIMAL(5, 4))
    FROM kafka_sales_person sp
    LEFT JOIN kafka_person          p ON p.business_entity_id = sp.business_entity_id
    LEFT JOIN kafka_sales_territory t ON t.territory_id       = sp.territory_id;

    INSERT INTO iceberg_catalog.gold.dim_currency
    SELECT currency_code, name AS currency_name FROM kafka_currency;

    ----------------------------------------------------------------
    -- 6.3  Gold: sales fact at the order-line grain
    --      Join is a regular streaming join on primary keys; both
    --      sides are upsert sources, so Flink maintains the latest
    --      state per (order_id, detail_id) and emits a single
    --      upsert per change to either header or detail.
    ----------------------------------------------------------------
    INSERT INTO iceberg_catalog.gold.fact_sales_order_line
    SELECT
        d.sales_order_id,
        d.sales_order_detail_id,
        TO_TIMESTAMP_LTZ(h.order_date / 1000, 3)                         AS order_ts,
        TO_DATE(FROM_UNIXTIME(CAST(h.order_date / 1000000 AS BIGINT)))   AS order_date,
        h.customer_id,
        d.product_id,
        h.territory_id,
        h.sales_person_id,
        h.currency_code,
        h.status                                                         AS order_status,
        d.order_qty,
        CAST(d.unit_price          AS DECIMAL(12, 4)),
        CAST(d.unit_price_discount AS DECIMAL(5, 4)),
        CAST(d.order_qty * CAST(d.unit_price AS DECIMAL(20, 6))
             AS DECIMAL(20, 6))                                          AS gross_amount,
        CAST(d.order_qty
             * CAST(d.unit_price          AS DECIMAL(20, 6))
             * CAST(d.unit_price_discount AS DECIMAL(20, 6))
             AS DECIMAL(20, 6))                                          AS discount_amount,
        CAST(d.order_qty
             * CAST(d.unit_price AS DECIMAL(20, 6))
             * (CAST(1 AS DECIMAL(20, 6))
                - CAST(d.unit_price_discount AS DECIMAL(20, 6)))
             AS DECIMAL(20, 6))                                          AS line_total
    FROM kafka_sales_order_detail d
    JOIN kafka_sales_order_header h
      ON h.sales_order_id = d.sales_order_id;
END;
