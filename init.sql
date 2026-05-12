-- =====================================================================
-- AdventureWorks (PostgreSQL subset) — operational source for CDC pipeline
-- =====================================================================
-- This is a slimmed-down, PostgreSQL-compatible port of the Microsoft
-- AdventureWorks sample database, focused on the sales domain that feeds
-- the analytical star schema in the Lakehouse (Apache Iceberg).
--
-- Schemas:
--   person      — people (customers and employees are persons)
--   production  — products and product hierarchy
--   sales       — territories, currencies, customers, salespeople, orders
--
-- The schema is intentionally compact (≈10 tables) so the whole CDC
-- pipeline (Debezium → Kafka → Flink → Iceberg) stays easy to demo
-- end-to-end, while still producing a realistic star schema downstream.
-- =====================================================================

CREATE SCHEMA person;
CREATE SCHEMA production;
CREATE SCHEMA sales;

-- ---------------------------------------------------------------------
-- person.person
-- ---------------------------------------------------------------------
CREATE TABLE person.person (
    business_entity_id  SERIAL PRIMARY KEY,
    person_type         VARCHAR(2)  NOT NULL,                -- IN = Customer, EM = Employee, SP = SalesPerson
    first_name          VARCHAR(50) NOT NULL,
    last_name           VARCHAR(50) NOT NULL,
    email_address       VARCHAR(100),
    modified_date       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- production.product_category / product_subcategory / product
-- ---------------------------------------------------------------------
CREATE TABLE production.product_category (
    product_category_id  SERIAL PRIMARY KEY,
    name                 VARCHAR(50) NOT NULL,
    modified_date        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE production.product_subcategory (
    product_subcategory_id SERIAL PRIMARY KEY,
    product_category_id    INT NOT NULL REFERENCES production.product_category(product_category_id),
    name                   VARCHAR(50) NOT NULL,
    modified_date          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE production.product (
    product_id              SERIAL PRIMARY KEY,
    product_subcategory_id  INT REFERENCES production.product_subcategory(product_subcategory_id),
    name                    VARCHAR(100)   NOT NULL,
    product_number          VARCHAR(25)    NOT NULL UNIQUE,
    color                   VARCHAR(20),
    standard_cost           DECIMAL(12, 4) NOT NULL,
    list_price              DECIMAL(12, 4) NOT NULL,
    size                    VARCHAR(10),
    weight                  DECIMAL(8, 2),
    sell_start_date         DATE NOT NULL,
    sell_end_date           DATE,
    modified_date           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- sales.sales_territory / currency / customer / sales_person
-- ---------------------------------------------------------------------
CREATE TABLE sales.sales_territory (
    territory_id    SERIAL PRIMARY KEY,
    name            VARCHAR(50) NOT NULL,
    country_region  VARCHAR(3)  NOT NULL,
    "group"         VARCHAR(50) NOT NULL,
    modified_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales.currency (
    currency_code  CHAR(3) PRIMARY KEY,
    name           VARCHAR(50) NOT NULL,
    modified_date  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales.customer (
    customer_id          SERIAL PRIMARY KEY,
    person_id            INT REFERENCES person.person(business_entity_id),
    territory_id         INT REFERENCES sales.sales_territory(territory_id),
    account_number       VARCHAR(10) NOT NULL UNIQUE,
    customer_segment     VARCHAR(20) NOT NULL DEFAULT 'Retail', -- Retail, Wholesale, Corporate
    modified_date        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales.sales_person (
    business_entity_id  INT PRIMARY KEY REFERENCES person.person(business_entity_id),
    territory_id        INT REFERENCES sales.sales_territory(territory_id),
    sales_quota         DECIMAL(12, 2),
    commission_pct      DECIMAL(5, 4) NOT NULL DEFAULT 0.0,
    modified_date       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- sales.sales_order_header / sales_order_detail (the fact source)
-- ---------------------------------------------------------------------
CREATE TABLE sales.sales_order_header (
    sales_order_id        SERIAL PRIMARY KEY,
    order_date            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ship_date             TIMESTAMP,
    status                SMALLINT  NOT NULL DEFAULT 1, -- 1=InProcess, 2=Approved, 3=Backordered, 4=Rejected, 5=Shipped, 6=Cancelled
    customer_id           INT NOT NULL REFERENCES sales.customer(customer_id),
    sales_person_id       INT REFERENCES sales.sales_person(business_entity_id),
    territory_id          INT REFERENCES sales.sales_territory(territory_id),
    currency_code         CHAR(3) NOT NULL DEFAULT 'USD' REFERENCES sales.currency(currency_code),
    sub_total             DECIMAL(14, 4) NOT NULL DEFAULT 0,
    tax_amt               DECIMAL(14, 4) NOT NULL DEFAULT 0,
    freight               DECIMAL(14, 4) NOT NULL DEFAULT 0,
    total_due             DECIMAL(14, 4) NOT NULL DEFAULT 0,
    modified_date         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales.sales_order_detail (
    sales_order_id          INT NOT NULL REFERENCES sales.sales_order_header(sales_order_id),
    sales_order_detail_id   SERIAL,
    product_id              INT NOT NULL REFERENCES production.product(product_id),
    order_qty               SMALLINT NOT NULL,
    unit_price              DECIMAL(12, 4) NOT NULL,
    unit_price_discount     DECIMAL(5, 4)  NOT NULL DEFAULT 0,
    line_total              DECIMAL(38, 6) GENERATED ALWAYS AS
                            (order_qty * unit_price * (1 - unit_price_discount)) STORED,
    modified_date           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (sales_order_id, sales_order_detail_id)
);

-- =====================================================================
-- Replica identity — Debezium needs full row image for UPDATE/DELETE
-- to correctly emit "before" state for CDC envelopes.
-- =====================================================================
ALTER TABLE person.person                  REPLICA IDENTITY FULL;
ALTER TABLE production.product_category    REPLICA IDENTITY FULL;
ALTER TABLE production.product_subcategory REPLICA IDENTITY FULL;
ALTER TABLE production.product             REPLICA IDENTITY FULL;
ALTER TABLE sales.sales_territory          REPLICA IDENTITY FULL;
ALTER TABLE sales.currency                 REPLICA IDENTITY FULL;
ALTER TABLE sales.customer                 REPLICA IDENTITY FULL;
ALTER TABLE sales.sales_person             REPLICA IDENTITY FULL;
ALTER TABLE sales.sales_order_header       REPLICA IDENTITY FULL;
ALTER TABLE sales.sales_order_detail       REPLICA IDENTITY FULL;

-- =====================================================================
-- Helpful read-only indexes (do not affect CDC, just analytical queries
-- run directly against PostgreSQL during development).
-- =====================================================================
CREATE INDEX ix_order_header_customer  ON sales.sales_order_header (customer_id);
CREATE INDEX ix_order_header_date      ON sales.sales_order_header (order_date);
CREATE INDEX ix_order_detail_product   ON sales.sales_order_detail (product_id);

-- =====================================================================
-- SEED DATA
-- Small but realistic dataset to demonstrate the full star schema
-- (multiple territories, multiple categories, multiple orders per
-- customer, line-item discounts, etc.).
-- =====================================================================

-- Currencies
INSERT INTO sales.currency (currency_code, name) VALUES
    ('USD', 'US Dollar'),
    ('EUR', 'Euro'),
    ('GEL', 'Georgian Lari'),
    ('GBP', 'British Pound');

-- Sales territories
INSERT INTO sales.sales_territory (name, country_region, "group") VALUES
    ('Tbilisi',         'GE',  'Caucasus'),
    ('Batumi',          'GE',  'Caucasus'),
    ('Berlin',          'DE',  'Europe'),
    ('Paris',           'FR',  'Europe'),
    ('New York',        'US',  'North America'),
    ('London',          'GB',  'Europe');

-- Product categories
INSERT INTO production.product_category (name) VALUES
    ('Bikes'),
    ('Components'),
    ('Clothing'),
    ('Accessories');

-- Product subcategories
INSERT INTO production.product_subcategory (product_category_id, name) VALUES
    (1, 'Mountain Bikes'),
    (1, 'Road Bikes'),
    (1, 'Touring Bikes'),
    (2, 'Wheels'),
    (2, 'Brakes'),
    (3, 'Jerseys'),
    (3, 'Gloves'),
    (4, 'Helmets'),
    (4, 'Bottles');

-- Products
INSERT INTO production.product
    (product_subcategory_id, name, product_number, color, standard_cost, list_price, size, weight, sell_start_date)
VALUES
    (1, 'Mountain-100 Black',  'BK-M100-B', 'Black',  1200.00, 3399.99, 'L',  10.50, '2022-01-01'),
    (1, 'Mountain-200 Silver', 'BK-M200-S', 'Silver',  800.00, 2199.99, 'M',  11.20, '2022-03-01'),
    (2, 'Road-150 Red',        'BK-R150-R', 'Red',    1500.00, 3578.27, 'L',   9.40, '2022-01-01'),
    (2, 'Road-250 Black',      'BK-R250-B', 'Black',   900.00, 2443.35, 'M',   9.80, '2022-06-15'),
    (3, 'Touring-1000 Blue',   'BK-T100-U', 'Blue',   1100.00, 2384.07, 'L',  12.00, '2023-01-10'),
    (4, 'HL Road Wheelset',    'WH-R-HL',   'Black',   250.00,  559.99, NULL,  2.10, '2022-01-01'),
    (5, 'Disc Brake Set',      'BR-DISC-1', 'Silver',   80.00,  159.49, NULL,  0.90, '2022-01-01'),
    (6, 'Long-Sleeve Jersey',  'CL-LSL-01', 'Blue',     20.00,   49.99, 'M',   0.30, '2022-01-01'),
    (7, 'Half-Finger Gloves',  'CL-HFG-01', 'Black',    10.00,   24.99, 'M',   0.10, '2022-01-01'),
    (8, 'Sport Helmet',        'AC-HEL-01', 'Red',      35.00,   79.99, NULL,  0.40, '2022-01-01'),
    (9, 'Water Bottle 1L',     'AC-BTL-01', 'Clear',     2.00,    9.99, NULL,  0.10, '2022-01-01');

-- People (mix of Georgian and international names for a realistic local demo)
INSERT INTO person.person (person_type, first_name, last_name, email_address) VALUES
    ('SP', 'Giorgi',   'Maisuradze',   'giorgi.m@adventure.local'),
    ('SP', 'Nino',     'Beridze',      'nino.b@adventure.local'),
    ('SP', 'Anna',     'Schmidt',      'anna.s@adventure.local'),
    ('IN', 'Davit',    'Kapanadze',    'davit.k@example.com'),
    ('IN', 'Mariam',   'Tsiklauri',    'mariam.t@example.com'),
    ('IN', 'Levan',    'Gelashvili',   'levan.g@example.com'),
    ('IN', 'Tamar',    'Lomidze',      'tamar.l@example.com'),
    ('IN', 'John',     'Smith',        'john.smith@example.com'),
    ('IN', 'Marie',    'Dubois',       'marie.d@example.com'),
    ('IN', 'Hans',     'Mueller',      'hans.m@example.com'),
    ('IN', 'Oliver',   'Brown',        'oliver.b@example.com'),
    ('IN', 'Sophia',   'Rossi',        'sophia.r@example.com');

-- Salespeople (use person_ids 1..3 = type 'SP')
INSERT INTO sales.sales_person (business_entity_id, territory_id, sales_quota, commission_pct) VALUES
    (1, 1, 250000.00, 0.0150),  -- Giorgi -> Tbilisi
    (2, 2, 180000.00, 0.0125),  -- Nino   -> Batumi
    (3, 3, 300000.00, 0.0175);  -- Anna   -> Berlin

-- Customers (use person_ids 4..12 = type 'IN'). Each customer has a home territory.
INSERT INTO sales.customer (person_id, territory_id, account_number, customer_segment) VALUES
    (4,  1, 'AW00000001', 'Retail'),
    (5,  1, 'AW00000002', 'Retail'),
    (6,  2, 'AW00000003', 'Wholesale'),
    (7,  2, 'AW00000004', 'Retail'),
    (8,  5, 'AW00000005', 'Corporate'),
    (9,  4, 'AW00000006', 'Retail'),
    (10, 3, 'AW00000007', 'Wholesale'),
    (11, 6, 'AW00000008', 'Retail'),
    (12, 3, 'AW00000009', 'Corporate');

-- Orders. Spread across 3 months and across territories, with discounts.
-- Header rows:
INSERT INTO sales.sales_order_header
    (order_date, ship_date, status, customer_id, sales_person_id, territory_id, currency_code, sub_total, tax_amt, freight, total_due)
VALUES
    ('2026-01-05 10:15:00', '2026-01-07 09:00:00', 5, 1, 1, 1, 'GEL',  3399.99, 305.99,  35.00, 3740.98),
    ('2026-01-12 14:30:00', '2026-01-14 12:00:00', 5, 2, 1, 1, 'GEL',  2199.99, 198.00,  35.00, 2432.99),
    ('2026-01-20 09:45:00', '2026-01-22 16:30:00', 5, 3, 2, 2, 'USD',  3578.27, 286.26,  40.00, 3904.53),
    ('2026-02-02 11:00:00', '2026-02-04 10:00:00', 5, 4, 2, 2, 'USD',  2443.35, 195.46,  40.00, 2678.81),
    ('2026-02-15 16:20:00', '2026-02-18 11:00:00', 5, 5, 3, 5, 'USD',  2384.07, 190.72,  50.00, 2624.79),
    ('2026-02-22 13:10:00', '2026-02-25 09:30:00', 5, 6, 3, 4, 'EUR',  3399.99, 271.99,  45.00, 3717.98),
    ('2026-03-04 10:00:00', '2026-03-06 14:00:00', 5, 7, 3, 3, 'EUR',  2199.99, 175.99,  45.00, 2421.97),
    ('2026-03-11 15:25:00', '2026-03-13 11:00:00', 5, 8, 3, 6, 'GBP',  1599.96, 127.99,  40.00, 1767.95),
    ('2026-03-19 09:00:00', '2026-03-21 10:00:00', 5, 9, 3, 3, 'EUR',  1719.94, 137.59,  45.00, 1902.53);

-- Order details (line items)
INSERT INTO sales.sales_order_detail
    (sales_order_id, product_id, order_qty, unit_price, unit_price_discount)
VALUES
    -- Order 1: a single Mountain-100
    (1, 1, 1, 3399.99, 0.0000),
    -- Order 2: a single Mountain-200
    (2, 2, 1, 2199.99, 0.0000),
    -- Order 3: a Road-150 + accessory bundle
    (3, 3, 1, 3578.27, 0.0000),
    -- Order 4: a Road-250 with a 5% discount
    (4, 4, 1, 2572.00, 0.0500),
    -- Order 5: a Touring-1000
    (5, 5, 1, 2384.07, 0.0000),
    -- Order 6: a Mountain-100 + helmet
    (6, 1,  1, 3399.99, 0.0000),
    (6, 10, 1,   79.99, 0.0000),
    -- Order 7: a Mountain-200 + jersey + gloves
    (7, 2, 1, 2199.99, 0.0000),
    (7, 8, 1,   49.99, 0.0000),
    (7, 9, 1,   24.99, 0.0000),
    -- Order 8: bulk components — wholesale buyer
    (8, 6, 2,  559.99, 0.1000),
    (8, 7, 5,  159.49, 0.1000),
    -- Order 9: mixed retail basket
    (9, 8,  5, 49.99, 0.0500),
    (9, 9,  5, 24.99, 0.0000),
    (9, 10, 2, 79.99, 0.0000),
    (9, 11, 10, 9.99, 0.0000);
