-- ВАЖНО: Включаем checkpointing - без него Iceberg не коммитит данные в MinIO!
SET 'execution.checkpointing.interval' = '10s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

-- 1. Создаем Iceberg Каталог в отдельном пространстве имён.
CREATE CATALOG iceberg_catalog WITH (
  'type'='iceberg',
  'catalog-type'='hadoop',
  'warehouse'='s3a://lakehouse-admin/iceberg_data'
);

-- 2. Создаем базу данных в Iceberg
CREATE DATABASE IF NOT EXISTS iceberg_catalog.shop_analytics;

-- Дропаем старую таблицу если она существует со старой схемой
DROP TABLE IF EXISTS iceberg_catalog.shop_analytics.iceberg_orders;

-- 3. Kafka source таблица создаётся в DEFAULT каталоге (in-memory, не в Iceberg!)
USE CATALOG default_catalog;
USE default_database;

CREATE TABLE IF NOT EXISTS kafka_orders (
    id INT,
    customer_name STRING,
    product_id INT,
    price DECIMAL(10, 2),
    created_at BIGINT,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'kafka',
    'topic' = 'shop.shop.orders',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-iceberg-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json',
    'debezium-json.schema-include' = 'true',
    'debezium-json.ignore-parse-errors' = 'true'
);

-- 4. Iceberg sink таблица создаётся в Iceberg каталоге
CREATE TABLE IF NOT EXISTS iceberg_catalog.shop_analytics.iceberg_orders (
    id INT,
    customer_name STRING,
    product_id INT,
    price DECIMAL(10, 2),
    created_at BIGINT,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'format-version'='2',
    'write.upsert.enabled'='true'
);

-- 5. Поток данных: Kafka (default_catalog) -> Iceberg (iceberg_catalog)
INSERT INTO iceberg_catalog.shop_analytics.iceberg_orders
SELECT * FROM default_catalog.default_database.kafka_orders;
