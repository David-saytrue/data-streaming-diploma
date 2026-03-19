-- Создаем схему и таблицу заказов для нашего интернет-магазина
CREATE SCHEMA shop;

CREATE TABLE shop.orders (
    id SERIAL PRIMARY KEY,
    customer_name VARCHAR(100),
    product_id INT,
    price DECIMAL(10, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Важно дать права репликации пользователю, 
-- но так как у нас дефолтный postgres - он суперюзер. Просто вставляем данные.

INSERT INTO shop.orders (customer_name, product_id, price) VALUES 
('Ivan Ivanov', 101, 550.00),
('Petr Petrov', 202, 1200.50),
('Maria Sidorova', 101, 550.00);
