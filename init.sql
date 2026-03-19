-- Create schema and orders table for our e-commerce store
CREATE SCHEMA shop;

CREATE TABLE shop.orders (
    id SERIAL PRIMARY KEY,
    customer_name VARCHAR(100),
    product_id INT,
    price DECIMAL(10, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- We need to grant replication privileges to the user, 
-- but since we are using the default postgres user, it's already a superuser. 
-- Just seeding some dummy data to start with.

INSERT INTO shop.orders (customer_name, product_id, price) VALUES 
('Ivan Ivanov', 101, 550.00),
('Petr Petrov', 202, 1200.50),
('Maria Sidorova', 101, 550.00);
