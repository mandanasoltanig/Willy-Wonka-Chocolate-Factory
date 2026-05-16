USE willy_wonka;
-- Creating tables 
CREATE TABLE customers (

    customer_id   INT          PRIMARY KEY,

    country       VARCHAR(100),

    city          VARCHAR(100),

    state         VARCHAR(100),

    postal_code   VARCHAR(20)

);

CREATE TABLE factories (

    factory_id    INT          PRIMARY KEY,

    factory_name  VARCHAR(100),

    latitude      DECIMAL(10,6),

    longitude     DECIMAL(10,6)

);

CREATE TABLE products (

    product_id    INT          PRIMARY KEY,

    product_name  VARCHAR(200),

    division      VARCHAR(100)

);

CREATE TABLE orders (

    order_id      INT          PRIMARY KEY,

    order_date    DATE,

    ship_date     DATE,

    ship_mode     VARCHAR(50),

    region        VARCHAR(100),

    customer_id   INT,

    product_id    INT,

    factory_id    INT,

    sales         DECIMAL(10,2),

    units         INT,

    gross_profit  DECIMAL(10,2),

    cost          DECIMAL(10,2),

    FOREIGN KEY (customer_id)  REFERENCES customers(customer_id),

    FOREIGN KEY (product_id)   REFERENCES products(product_id),

    FOREIGN KEY (factory_id)   REFERENCES factories(factory_id)

);
-- The reason we used a staging table in between is because CSV is one flat file with everything mixed together — customer info, product info, factory info, all in one row. So had to:

 

-- Dump it into staging_raw as-is

-- Then split and sort that data into the 4 normalised tables

-- 1. populate customers

INSERT INTO customers (customer_id, country, city, state, postal_code)

SELECT DISTINCT `Customer ID`, `Country/Region`, `City`, `State/Province`, `Postal Code`

FROM staging_raw;

-- 2. populate factories

INSERT INTO factories (factory_id, factory_name, latitude, longitude)

SELECT ROW_NUMBER() OVER (ORDER BY Factory) AS factory_id,

       Factory, Latitude, Longitude

FROM (SELECT DISTINCT Factory, Latitude, Longitude FROM staging_raw) f ;

-- 3. populate products

INSERT INTO products (product_id, product_name, division)

SELECT ROW_NUMBER() OVER (ORDER BY `Product Name`) AS product_id,

       `Product Name`, Division

FROM (SELECT DISTINCT `Product Name`, Division FROM staging_raw) p;

-- 4. populate orders

INSERT INTO orders (order_id, order_date, ship_date, ship_mode, region,

                    customer_id, product_id, factory_id, sales, units, gross_profit, cost)

SELECT

    ROW_NUMBER() OVER (ORDER BY s.`Order Date`) AS order_id,

    STR_TO_DATE(s.`Order Date`, '%Y-%m-%d'),

    STR_TO_DATE(s.`Ship Date`,  '%Y-%m-%d'),

    s.`Ship Mode`,

    s.Region,

    s.`Customer ID`,

    p.product_id,

    f.factory_id,

    s.Sales,

    s.Units,

    s.`Gross Profit`,

    s.Cost

FROM staging_raw s

JOIN products  p ON p.product_name = s.`Product Name`

JOIN factories f ON f.factory_name = s.Factory;


select * from factories;

-- H1 Q4 seasonality drives revenue 

-- 1 monthly sales totals across all years 
SELECT 
    YEAR(order_date) AS order_year,
    MONTH(order_date) AS order_month,
    MONTHNAME(order_date) AS month_name,

    ROUND(SUM(sales), 2) AS total_sales,

    ROUND(SUM(gross_profit), 2) AS total_gp,

    SUM(units) AS total_units

FROM orders

GROUP BY
    YEAR(order_date),
    MONTH(order_date),
    MONTHNAME(order_date)

ORDER BY
    order_year ASC,
    order_month ASC;
 
 -- compare Q4 vs non Q4 comparison
 -- 2. Q4 vs Non-Q4 comparison
SELECT 
CASE 
WHEN MONTH(order_date) IN (10, 11, 12) THEN 'Q4'
ELSE 'Non-Q4'
END AS period,

ROUND(SUM(sales), 2) AS total_sales,
ROUND(SUM(gross_profit), 2) AS total_gp,
SUM(units) AS total_units,
ROUND(AVG(sales), 2) AS avg_order_sales

FROM orders

GROUP BY
CASE 
WHEN MONTH(order_date) IN (10, 11, 12) THEN 'Q4'
ELSE 'Non-Q4'
END

ORDER BY
total_sales DESC;

-- 3.Quarterly sales comparison
-- 3. Quarterly sales comparison
SELECT
    QUARTER(order_date) AS quarter_number,

    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(gross_profit), 2) AS total_gp,
    SUM(units) AS total_units

FROM orders

GROUP BY
    QUARTER(order_date)

ORDER BY
    quarter_number DESC;
 
-- 4 Best Performing months
-- identifies the strongest months overall
SELECT
    MONTHNAME(o.order_date) AS month_name,

    ROUND(SUM(o.sales), 2) AS total_sales,

    ROUND(SUM(o.gross_profit), 2) AS total_profit

FROM orders o

GROUP BY
    MONTH(o.order_date),
    MONTHNAME(o.order_date)

ORDER BY total_sales DESC;

 -- 5. Peak Revenue Months
-- Finds months with above-average sales
SELECT
MONTHNAME(o.order_date) AS month_name,

ROUND(SUM(o.sales), 2) AS total_sales

FROM orders o

GROUP BY
MONTH(o.order_date),
MONTHNAME(o.order_date)

HAVING SUM(o.sales) >
(
SELECT AVG(monthly_sales)
FROM (
SELECT
SUM(sales) AS monthly_sales
FROM orders
GROUP BY 
YEAR(order_date),
MONTH(order_date)
) avg_table
)

ORDER BY total_sales DESC;
-- Findings

-- The analysis showed that Q4 generated higher overall sales and stronger average monthly revenue compared to non-Q4 periods. Monthly trend analysis revealed noticeable spikes in revenue during the final months of the year, supporting the assumption that seasonality impacts chocolate demand.

-- Quarterly aggregation further demonstrated that Q4 outperformed other quarters in total sales and gross profit.

-- Hypothesis2:
-- factory efficiency varies. lot's O'Nuts dominates volumebut does it lead on margin?
-- the secret factory may puch above its weight
USE willy_wonka;
SELECT
    f.factory_name,

    COUNT(o.order_id) AS total_orders,
    SUM(o.units) AS total_units,
    SUM(o.sales) AS total_sales,
    SUM(o.gross_profit) AS total_gross_profit,
    SUM(o.cost) AS total_cost,

    ROUND(SUM(o.gross_profit) / SUM(o.sales) * 100, 2) AS profit_margin_percent,

    ROUND(
        SUM(o.units) / SUM(SUM(o.units)) OVER () * 100,
        2
    ) AS volume_share_percent,

    ROUND(
        SUM(o.gross_profit) / SUM(SUM(o.gross_profit)) OVER () * 100,
        2
    ) AS profit_share_percent,

    ROUND(
        (
            SUM(o.gross_profit) / SUM(SUM(o.gross_profit)) OVER ()
        ) -
        (
            SUM(o.units) / SUM(SUM(o.units)) OVER ()
        ),
        4
    ) AS profit_vs_volume_gap

FROM orders o
JOIN factories f
    ON o.factory_id = f.factory_id

GROUP BY
    f.factory_id,
    f.factory_name

ORDER BY
    total_units DESC;
    
-- Factory profitability varies significantly. Lot’s O’ Nuts is the clear leader, 
-- dominating both volume and margin,(55.50% of total units ,56.61% of total gross profit,69.13% profit margin) 
-- so high volume does translate into strong profitability for this factory. 
-- However, Secret Factory punches above its weight: despite producing only 2.30% of total units, it generates 4.59% of total gross profit. 
-- This suggests Secret Factory is small but relatively valuable, 
-- while Wicked Choccy’s has high volume but slightly weaker profit contributed.

-- H3 :"Regional Concentration":
-- Some regions bring in way more revenue than others — the business is heavily dependent on a few regions rather than being spread evenly.

-- Total sales by region
SELECT
    region,
    ROUND(SUM(sales), 2) AS total_sales,
    SUM(units)           AS total_units,
    COUNT(*)             AS order_count
    FROM orders
    GROUP BY region
    ORDER BY total_sales DESC;
    
-- Each region's % share of total revenue 
-- 2 regions make up about 60-61% of revenue
SELECT
    region,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(sales) / (SELECT SUM(sales) FROM orders) * 100 , 2) AS percentage_of_total_revenue -- Inner part calculates total sales from whole table and outer part is Regional Percentage
    FROM orders
    GROUP BY region
    ORDER BY percentage_of_total_revenue DESC;
    
-- Breakdown to city and state level    
    
SELECT
    c.state,
    c.city,
    ROUND(SUM(o.sales), 2) AS total_sales, -- adds all sales for each city
    COUNT(*)                    AS order_count -- number of orders in that city
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id -- joins orders table has sales data with customers table has ity and state
    GROUP BY c.state, c.city -- groups rows based on state and city
    ORDER BY total_sales DESC
    LIMIT 10;
    
-- Pacific region (California + Washington) has cities appearing 4 out of 10 times
-- Atlantic region (New York + Pennsylvania) appearing 3 out of 10 times
-- Together that perfectly explains why Pacific + Atlantic = 60-61% of total revenue 

-- Revenue is heavily concentrated in a few major cities — New York City and Los Angeles 
-- alone drive the most orders and sales. 
-- This confirms that Wonka's business is not evenly spread geographically but dependent on a small number of urban centers.


   
