-- Products carried by the retail store
CREATE TABLE products2(
	product_id INTEGER PRIMARY KEY AUTOINCREMENT,
	name TEXT NOT NULL,
	category TEXT,
	unit_cost REAL NOT NULL
);
SELECT * FROM products2;

-- Inventory transactions:: Records of sales restocks (for FSN)
CREATE TABLE inventory_movements1(
	movement_id INTEGER PRIMARY KEY AUTOINCREMENT,
	product_id INTEGER,
	movement_type TEXT,  -- 'IN' (purchase) or 'OUT' (sale)
	qty REAL,
	movement_date DATE,
	FOREIGN KEY (product_id) REFERENCES products2(product_id)
);
SELECT * FROM inventory_movements1;

-- Inventory stock:: Current stock levels
CREATE TABLE stock_levels(
	product_id INTEGER PRIMARY KEY,
	current_qty REAL,
	last_update DATE,
	FOREIGN KEY(product_id) REFERENCES products2(product_id)
);
SELECT * FROM stock_levels;
	
-- Auxiliary table:: Define ABC/FSN thresholds for easy scenario testing
CREATE TABLE classification_settings(
	param TEXT PRIMARY KEY,
	value REAL
);
SELECT * FROM classification_settings;

-- Products:: name, category, unit_cost (simulate diversity by cost, category)
INSERT INTO products2(name, category, unit_cost) VALUES
('Premium Mixer Grinder', 'Appliances', 4000),
('Regular Mixer Grinder', 'Appliances', 1800),
('LED Smart TV 43', 'Electronics', 23000),
('LED Smart TV 32', 'Electronics', 15000),
('Organic Almonds 1kg', 'Groceries', 950),
('Toothpaste 150g', 'Personal care', 100),
('Shampoo 1L', 'Personal Care', 450),
('Instant Coffee 100 g', 'Groceries', 250),
('Sports Water Bottle', 'Sports', 500),
('Wireless Mouse', 'Electronics', 600);

-- Inventory movements:: History for both Sales (OUT) and purchases (IN)

-- For simplicity, simulate for one quarter (Apr-Jun 2025)
INSERT INTO inventory_movements1(product_id, movement_type, qty, movement_date) VALUES

-- Heavy sales for Mixer Grinder
(1, 'OUT', 55, '2025-04-05'), (1, 'IN', 60, '2025-04-01'), (1, 'OUT', 40, '2025-05-03'), (1, 'OUT', 20, '2025-06-05'),

-- Steadier but lower sales for Regular Mixer
(2, 'OUT', 35, '2025-04-12'), (2, 'IN', 50, '2025-04-01'), (2, 'OUT', 33, '2025-05-28'), (2, 'OUT', 22, '2025-06-15'),

-- Expensive TV, rare sales
(3, 'OUT', 2, '2025-04-18'), (3, 'IN', 8, '2025-04-10'), (3, 'OUT', 2, '2025-06-02'),

-- Cheaper TV , moderate sales
(4, 'OUT', 8, '2025-05-10'), (4, 'IN', 12, '2025-05-01'), (4, 'OUT', 6, '2025-06-12'),

-- AlmoNds-frequently moving
(5, 'OUT', 120, '2025-04-15'), (5, 'IN', 180, '2025-04-03'), (5, 'OUT', 134, '2025-05-15'),

-- Toothpaste-very high sales
(6, 'OUT', 420, '2025-04-18'), (6, 'IN', 600, '2025-04-02'), (6, 'OUT', 410, '2025-06-01'),

-- Shampoo-slow sales
(7, 'OUT', 50, '2025-05-01'), (7, 'IN', 60, '2025-04-09'), (7, 'OUT', 45, '2025-06-27'),

-- Coffee-seasonal
(8, 'OUT', 90, '2025-04-12'), (8, 'IN', 110, '2025-03-28'), (8, 'OUT', 15, '2025-05-02'), (8, 'OUT', 9, '2025-06-15'),

-- Water Bottle-slow moving
(9, 'OUT', 10, '2025-04-09'), (9, 'IN', 20, '2025-04-01'), (9, 'OUT', 5, '2025-05-22'), 

-- Mouse-medium sales
(10, 'OUT', 25, '2025-05-06'), (10, 'IN', 30, '2025-04-02'), (10, 'OUT', 18, '2025-06-21');

-- Stock levels
INSERT INTO stock_levels(product_id, current_qty, last_update) VALUES
(1, 5, '2025-07-01'), (2, 17, '2025-07-01'), (3, 4, '2025-07-01'), (4, 3, '2025-07-01'), (5, 26, '2025-07-01'),
(6, 65, '2025-07-01'), (7, 18, '2025-07-01'), (8, 6, '2025-07-01'), (9, 5, '2025-07-01'), (10, 7, '2025-07-01');

-- Classification thresholds
INSERT INTO classification_settings(param, value) VALUES
('abc _a_pct', 0.8), -- 80% of cumulative annual value = A
('abc_b_pct', 0.95), -- to 95% = B, rest = C
('fsn_fast_itrr', 3), -- ITR > 3 = Fast
('fsn_slow_itrr', 1); -- 1 < ITR <= 3 = Slow, else Non-moving

-- 1. Calculate total consumption value (Unit Cost x Sales Qty in Q2 2025)
WITH consumption AS (
    SELECT
        p.product_id,
        p.name,
        sum(CASE WHEN im.movement_type='OUT' THEN im.qty ELSE 0 END) AS total_out,
        p.unit_cost,
        sum(CASE WHEN im.movement_type='OUT' THEN im.qty ELSE 0 END) * p.unit_cost AS total_value
    FROM products2 p
    LEFT JOIN inventory_movements1 im ON im.product_id = p.product_id
    WHERE im.movement_date BETWEEN '2025-04-01' AND '2025-06-30'
    GROUP BY p.product_id
),
-- Rank items for ABC
cons_ranked AS (
    SELECT *,
           ROUND(total_value * 1.0 / (SELECT SUM(total_value) FROM consumption), 3) AS pct_of_total
    FROM consumption
    ORDER BY total_value DESC
),
cum_pct AS (
    SELECT *,
           ROUND(SUM(pct_of_total) OVER (ORDER BY total_value DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),3) AS cum_pct
    FROM cons_ranked
)
SELECT
    product_id, name, total_out, unit_cost, total_value,
    CASE
        WHEN cum_pct <= 0.8 THEN 'A'
        WHEN cum_pct <= 0.95 THEN 'B'
        ELSE 'C'
    END AS abc_class
FROM cum_pct;

-- 1.Calculate total movements and ITR for Q2 2025
WITH sales AS(
	SELECT p.product_id,
		   p.name,
		   SUM(CASE WHEN im.movement_type = 'OUT' THEN im.qty ELSE 0 END) AS sales_qty,
		   avg(sl.current_qty) AS avg_inventory
	FROM products2 p
	LEFT JOIN inventory_movements1 im ON im.product_id = p.product_id
	LEFT JOIN stock_levels sl ON sl.product_id = p.product_id
	WHERE im.movement_date BETWEEN '2025-04-01' AND '2025-06-30'
	GROUP BY p.product_id
)
SELECT 
	product_id, name, sales_qty, avg_inventory,
	CASE
		WHEN (sales_qty * 1.0 / COALESCE(avg_inventory,1)) > 3 THEN 'F' -- 'Fast'
		WHEN (sales_qty * 1.0 / COALESCE(avg_inventory,1)) > 1 THEN 'S' -- 'Slow'
		ELSE 'N' -- Non-moving
	END AS fsn_class
FROM sales;

-- Combine ABC & FSN classification for actionable prioritization
WITH abc AS(
	-- Use results from previous ABC query (or create a VIEW for reuse)
	SELECT product_id, name,
	CASE
		WHEN cum_pct <= 0.8 THEN 'A'
		WHEN cum_pct <= 0.95 THEN 'B'
		ELSE 'C'
	END AS abc_class
FROM (
	SELECT *,
			ROUND(SUM(pct_of_total) OVER (ORDER BY total_value DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 3) AS cum_pct
	FROM (
		SELECT 
			p.product_id,
			p.name,
			sum(CASE WHEN im.movement_type = 'OUT' THEN im.qty ELSE 0 END) AS total_out,
			p.unit_cost,
			sum(CASE WHEN im.movement_type = 'OUT' THEN im.qty ELSE 0 END) * p.unit_cost AS total_value,
			ROUND(sum(CASE WHEN im.movement_type = 'OUT' THEN im.qty ELSE 0 END) * p.unit_cost)
			FROM products2 p
			LEFT JOIN inventory_movements1 im ON im.product_id = p.product_id
			WHERE im.movement_date BETWEEN '2025-04-01' AND '2025-06-30'
			GROUP BY p.product_id
		)
	)
),
fsn AS (
	SELECT p.product_id,
		CASE
			WHEN(sum(CASE WHEN im.movement_type = 'OUT' THEN im.qty ELSE 0 END) * 1.0 / COALESCE(avg(sl.current_qty), 1)) > 3 THEN 'F'
			WHEN(sum(CASE WHEN im.movement_type = 'OUT' THEN im.qty ELSE 0 END) * 1.0 / COALESCE(avg(sl.current_qty), 1)) > 1 THEN 'S'
			ELSE 'N'
		END AS fsn_class
	FROM products2 p
	LEFT JOIN inventory_movements1 im ON im.productid = p.productid
	LEFT JOIN stock_levels sl ON sl.product_id = p.product_id
	WHERE im.movement_date BETWEEN '2025-04-01' AND '2025-06-30'
	GROUP BY p.product_id
)
SELECT abc.product_id, abc.name, abc.abc_class, fsn.fsn_class
FROM abc
JOIN fsn ON abc.product_id = fsn.product_id 
ORDER BY abc.abc_class, fsn.fsn_class;
