DROP TABLE IF EXISTS walmart_sales;
DROP TABLE IF EXISTS walmart_staging;

-- 2. Create staging table with ALL TEXT columns (Prevents any import errors)
CREATE TABLE walmart_staging (
    invoice_id TEXT,
    branch TEXT,
    city TEXT,
    category TEXT,
    unit_price TEXT,
    quantity TEXT,
    sale_date TEXT,
    sale_time TEXT,
    payment_method TEXT,
    rating TEXT,
    profit_margin TEXT
);

-- 3. Copy the cleaned CSV into staging


-- 4. Create your final production table with proper data types
CREATE TABLE walmart_sales (
    invoice_id INT PRIMARY KEY,
    branch VARCHAR(10) NOT NULL,
    city VARCHAR(50) NOT NULL,
    category VARCHAR(50) NOT NULL,
    unit_price DECIMAL(10, 2),
    quantity INT,
    sale_date DATE,
    sale_time TIME,
    payment_method VARCHAR(30) NOT NULL,
    rating DECIMAL(3, 1) NOT NULL,
    profit_margin DECIMAL(5, 4) NOT NULL
);

-- 5. Insert and safely cast data from staging to final table
INSERT INTO walmart_sales (
    invoice_id,
    branch,
    city,
    category,
    unit_price,
    quantity,
    sale_date,
    sale_time,
    payment_method,
    rating,
    profit_margin
)
SELECT 
    invoice_id::INT,
    branch,
    city,
    category,
    unit_price::DECIMAL(10, 2),
    quantity::INT, -- Now works smoothly because Python exported clean integers
    TO_DATE(sale_date, 'DD/MM/YY'),
    sale_time::TIME,
    payment_method,
    rating::DECIMAL(3, 1),
    profit_margin::DECIMAL(5, 4)
FROM walmart_staging
WHERE invoice_id ~ '^[0-9]+$';

-- 6. Clean up staging table
DROP TABLE walmart_staging;
select * from walmart_sales;
-- 7. Verify your data loaded successfully!
SELECT COUNT(*) FROM walmart_sales;
SELECT * FROM walmart_sales;
SELECT * FROM walmart_sales LIMIT 5;

---Q1: Top-Performing Product Categories by Total Revenue & Profit
---Business Objective: Identify which product categories generate the highest gross revenue 
--and total profit to guide inventory allocation.
SELECT 
    category,
    COUNT(invoice_id) AS total_transactions,
    SUM(unit_price * quantity) AS total_revenue,
    ROUND(SUM((unit_price * quantity) * profit_margin), 2) AS total_profit,
    ROUND(AVG(rating), 2) AS avg_rating
FROM walmart_sales
WHERE unit_price IS NOT NULL AND quantity IS NOT NULL
GROUP BY category
ORDER BY total_revenue DESC;


----Category performance
SELECT
    category,
    COUNT(*) AS total_transactions,
    SUM(quantity) AS units_sold,
    ROUND(AVG(rating), 2) AS average_rating
FROM walmart_sales
GROUP BY category;

---Q2. Branch performance ranking
CREATE OR REPLACE VIEW vw_walmart_valid_sales AS
SELECT
    invoice_id,
    branch,
    city,
    category,
    unit_price,
    quantity,
    sale_date,
    sale_time,
    payment_method,
    rating,
    profit_margin,
    unit_price * quantity AS revenue,

    ROUND(
        (unit_price * quantity * profit_margin)::NUMERIC,
        2
    ) AS estimated_profit

FROM walmart_sales
WHERE
    unit_price IS NOT NULL
    AND quantity > 0;
---Q1. Category performance
	SELECT
    category,
    COUNT(*) AS total_transactions,
    SUM(quantity) AS units_sold,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(SUM(estimated_profit), 2) AS estimated_profit,
    ROUND(AVG(rating), 2) AS average_rating
FROM vw_walmart_valid_sales
GROUP BY category
ORDER BY total_revenue DESC;

---Q2. Branch performance ranking
SELECT
    branch,
    city,
    COUNT(*) AS total_transactions,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(SUM(estimated_profit), 2) AS estimated_profit,
    RANK() OVER (
        ORDER BY SUM(revenue) DESC
    ) AS revenue_rank
FROM vw_walmart_valid_sales
GROUP BY branch, city
ORDER BY revenue_rank;

---Q3. Monthly revenue trend
SELECT
    DATE_TRUNC('month', sale_date)::DATE AS sales_month,
    ROUND(SUM(revenue), 2) AS monthly_revenue,
    ROUND(SUM(estimated_profit), 2) AS monthly_profit
FROM vw_walmart_valid_sales
GROUP BY DATE_TRUNC('month', sale_date)
ORDER BY sales_month;

---Q4. Payment method performance
SELECT
    payment_method,
    COUNT(*) AS transactions,
    SUM(quantity) AS units_sold,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(
        SUM(revenue) / COUNT(*),
        2
    ) AS avg_transaction_value
FROM vw_walmart_valid_sales
GROUP BY payment_method
ORDER BY total_revenue DESC;

---Q5. Peak shopping hours
SELECT
    EXTRACT(HOUR FROM sale_time) AS sales_hour,
    COUNT(*) AS total_transactions,
    ROUND(SUM(revenue), 2) AS total_revenue
FROM vw_walmart_valid_sales
GROUP BY EXTRACT(HOUR FROM sale_time)
ORDER BY total_transactions DESC;

---Q6. Top 10 branches by estimated profit
SELECT
    branch,
    city,
    ROUND(SUM(estimated_profit), 2) AS total_profit
FROM vw_walmart_valid_sales
GROUP BY branch, city
ORDER BY total_profit DESC
LIMIT 10;

-- Q5. City performance
SELECT
    city,
    COUNT(*) AS transactions,
    ROUND(SUM(revenue), 2) AS revenue,
    ROUND(AVG(rating), 2) AS average_rating
FROM vw_walmart_valid_sales
WHERE revenue IS NOT NULL
GROUP BY city
ORDER BY revenue DESC
LIMIT 10;

-- Q6. Payment method contribution
SELECT
   payment_method
ORDER BY revenue DESC;
    COUNT(*) AS transactions,
    ROUND(SUM(revenue), 2) AS revenue,
    ROUND(100.0 * SUM(revenue) / NULLIF(SUM(SUM(revenue)) OVER (), 0), 2)
          AS revenue_percentage
FROM vw_walmart_valid_sales
WHERE revenue IS NOT NULL
GROUP BY payment_method
ORDER BY revenue DESC;

-- Q7. Best-selling categories by quantity
SELECT
    category,
    SUM(quantity) AS units_sold,
    DENSE_RANK() OVER (ORDER BY SUM(quantity) DESC) AS quantity
FROM vw_walmart_valid_sales
GROUP BY category
ORDER BY quantity;
select * from vw_walmart_valid_sales;


-- Q8. Day-of-week performance
SELECT
    TO_CHAR(sale_date, 'Day') AS weekday,
    EXTRACT(ISODOW FROM sale_date) AS weekday_number,
    COUNT(*) AS transactions,
    ROUND(SUM(revenue), 2) AS revenue
FROM vw_walmart_valid_sales
WHERE revenue IS NOT NULL
GROUP BY weekday, weekday_number
ORDER BY weekday_number;

-- Q9. Hourly sales pattern
SELECT
    EXTRACT(HOUR FROM sale_time)::INTEGER AS sale_hour,
    COUNT(*) AS transactions,
    ROUND(SUM(revenue), 2) AS revenue
FROM vw_walmart_valid_sales
WHERE revenue IS NOT NULL AND sale_time IS NOT NULL
GROUP BY sale_hour
ORDER BY sale_hour;

-- Q10. High-rated categories (minimum 30 rated transactions)
SELECT
    category,
    COUNT(rating) AS rated_transactions,
    ROUND(AVG(rating), 2) AS average_rating
FROM vw_walmart_valid_sales
GROUP BY category
HAVING COUNT(rating) >= 30
ORDER BY average_rating DESC;

-- Q11. Branches performing above overall average revenue
WITH branch AS (
    SELECT branch, city, SUM(revenue) AS revenue
    FROM vw_walmart_valid_sales
    WHERE revenue IS NOT NULL
    GROUP BY branch, city
)
SELECT
    branch,
    city,
    ROUND(revenue, 2) AS branch,
    ROUND((SELECT AVG(revenue) FROM branch), 2) AS average_branch_revenue
FROM branch
WHERE revenue > (SELECT AVG(revenue) FROM branch)
ORDER BY revenue DESC;

-- Q12. Category revenue share using a window function
SELECT
    category,
    ROUND(SUM(revenue), 2) AS category,
    ROUND(
        100.0 * SUM(revenue) / NULLIF(SUM(SUM(revenue)) OVER (), 0),
        2
    ) AS revenue_share_pct
FROM vw_walmart_valid_sales
WHERE revenue IS NOT NULL
GROUP BY category
ORDER BY category DESC;

-- Q13. Month-over-month revenue change
WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', sale_date)::DATE AS sales_month,
        SUM(revenue) AS revenue
    FROM vw_walmart_valid_sales
    WHERE revenue IS NOT NULL
    GROUP BY 1
),
monthly_comparison AS (
    SELECT
        sales_month,
        revenue,
        LAG(revenue) OVER (ORDER BY sales_month) AS previous_month_revenue
    FROM monthly_sales
)
SELECT
    sales_month,
    ROUND(revenue, 2) AS revenue,
    ROUND(previous_month_revenue, 2) AS previous_month_revenue,
    ROUND(
        100.0 * (revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0),
        2
    ) AS mom_growth_pct
FROM monthly_comparison
ORDER BY sales_month;

-- Q14. Top 3 categories in each city
WITH city AS (
    SELECT
        city,
        category,
        SUM(revenue) AS revenue,
        DENSE_RANK() OVER (
            PARTITION BY city ORDER BY SUM(revenue) DESC
        ) AS category
    FROM vw_walmart_valid_sales
    WHERE revenue IS NOT NULL
    GROUP BY city, category
)
SELECT city, category, ROUND(revenue, 2) AS revenue, category
FROM city
WHERE category <= 3
ORDER BY city, category;


-- Q15. Transaction-level records requiring data review
SELECT *
FROM vw_walmart_valid_sales
WHERE quantity <>'VALID'
ORDER BY invoice_id;

select * from vw_walmart_valid_sales;
