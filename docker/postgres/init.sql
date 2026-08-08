CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    city TEXT NOT NULL,
    segment TEXT NOT NULL,
    created_at DATE NOT NULL
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    order_date DATE NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('paid', 'shipped', 'refunded')),
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    channel TEXT NOT NULL
);

INSERT INTO customers (name, city, segment, created_at) VALUES
    ('晨光书店', '杭州', '零售', '2026-01-12'),
    ('山海设计', '上海', '创意服务', '2026-02-03'),
    ('青禾咖啡', '成都', '餐饮', '2026-02-18'),
    ('北岸工作室', '北京', '软件服务', '2026-03-01'),
    ('松林民宿', '大理', '旅行', '2026-03-16'),
    ('云帆教育', '武汉', '教育', '2026-04-05');

INSERT INTO orders (customer_id, order_date, status, amount, channel) VALUES
    (1, '2026-06-02', 'paid',     1280.00, '官网'),
    (1, '2026-06-18', 'shipped',  860.00, '线下'),
    (2, '2026-06-05', 'paid',     3680.00, '转介绍'),
    (2, '2026-07-12', 'paid',     2450.00, '官网'),
    (2, '2026-07-28', 'refunded',  320.00, '官网'),
    (3, '2026-06-21', 'shipped',  1880.00, '线下'),
    (3, '2026-07-09', 'paid',      760.00, '官网'),
    (4, '2026-06-11', 'paid',     5200.00, '转介绍'),
    (4, '2026-07-24', 'shipped',  1980.00, '官网'),
    (5, '2026-07-03', 'paid',     1320.00, '线下'),
    (5, '2026-07-30', 'paid',      980.00, '官网'),
    (6, '2026-07-17', 'shipped',  4120.00, '转介绍');

CREATE INDEX orders_customer_id_idx ON orders(customer_id);
CREATE INDEX orders_order_date_idx ON orders(order_date);
