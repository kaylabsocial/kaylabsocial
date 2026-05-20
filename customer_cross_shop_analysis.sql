-- Purpose:
-- Analyze cross-shopping behavior across store brands within a specific market (CBSA),
-- enriched with customer demographics (income, age, segment).
-- Enables understanding of customer overlap and store-level performance.

WITH eligible_stores AS (
    SELECT 
        s.store_id,
        s.store_name,
        g.cbsa_code,
        g.cbsa_name
    FROM store_locations s
    LEFT JOIN geo_zip_to_cbsa g
        ON CAST(s.zip_code AS INT64) = g.zip_code
    WHERE g.cbsa_code = 'TARGET_CBSA'
        AND s.store_status = 'OPEN'
),

household_income AS (
    SELECT household_id, income_bracket, income_group
    FROM (
        SELECT 
            household_id,
            income_bracket,
            income_group,
            COUNT(*) AS cnt,
            ROW_NUMBER() OVER (
                PARTITION BY household_id 
                ORDER BY COUNT(*) DESC
            ) AS rn
        FROM customer_household_demographics
        GROUP BY household_id, income_bracket, income_group
    )
    WHERE rn = 1
),

individual_age AS (
    SELECT individual_id, age
    FROM (
        SELECT 
            individual_id,
            age,
            COUNT(*) AS cnt,
            ROW_NUMBER() OVER (
                PARTITION BY individual_id 
                ORDER BY COUNT(*) DESC
            ) AS rn
        FROM customer_individual_demographics
        GROUP BY individual_id, age
    )
    WHERE rn = 1
),

base AS (
    SELECT 
        t.customer_id,
        t.store_id,
        t.channel,
        d.year,
        d.period,
        g.cbsa_code,
        g.cbsa_name,
        p.category_name,
        seg.segment_name,
        hi.income_bracket,
        age.age,
        SUM(t.net_sales) AS net_sales,
        SUM(t.gross_sales) AS gross_sales
    FROM transactions t
    
    LEFT JOIN date_dim d 
        ON t.transaction_date = d.calendar_date
    
    LEFT JOIN customers c 
        ON t.customer_id = c.customer_id
    
    LEFT JOIN geo_tracts g 
        ON c.tract_id = g.tract_id
    
    LEFT JOIN product_dim p
        ON t.product_id = p.product_id
    
    LEFT JOIN customer_segments seg
        ON t.customer_id = seg.customer_id
    
    LEFT JOIN household_income hi
        ON c.household_id = hi.household_id
    
    LEFT JOIN individual_age age
        ON t.customer_id = age.individual_id
    
    INNER JOIN eligible_stores es
        ON t.store_id = es.store_id
    
    WHERE d.year IN (2024, 2025, 2026)
    
    GROUP BY 
        t.customer_id,
        t.store_id,
        t.channel,
        d.year,
        d.period,
        g.cbsa_code,
        g.cbsa_name,
        p.category_name,
        seg.segment_name,
        hi.income_bracket,
        age.age
),

shopper_segments AS (
    SELECT
        customer_id,
        CASE
            WHEN COUNT(DISTINCT store_id) = 1 THEN 'Single-Store'
            WHEN COUNT(DISTINCT store_id) > 1 THEN 'Cross-Shopper'
            ELSE 'Other'
        END AS shopper_type
    FROM base
    GROUP BY customer_id
),

final AS (
    SELECT
        b.year,
        b.period,
        b.cbsa_code,
        b.cbsa_name,
        b.channel,
        ss.shopper_type,
        b.store_id,
        b.category_name,
        
        -- Income Buckets
        CASE 
            WHEN b.income_bracket IN ('<50K') THEN 'Low Income'
            WHEN b.income_bracket IN ('50K-100K') THEN 'Mid Income'
            WHEN b.income_bracket IN ('100K+') THEN 'High Income'
            ELSE 'Unknown'
        END AS income_bucket,
        
        -- Age Buckets
        CASE 
            WHEN b.age BETWEEN 18 AND 29 THEN '18–29'
            WHEN b.age BETWEEN 30 AND 44 THEN '30–44'
            WHEN b.age BETWEEN 45 AND 60 THEN '45–60'
            WHEN b.age > 60 THEN '60+'
            ELSE 'Unknown'
        END AS age_bucket,
        
        COUNT(DISTINCT b.customer_id) AS customers,
        SUM(b.net_sales) AS total_net_sales,
        SUM(b.gross_sales) AS total_gross_sales

    FROM base b
    JOIN shopper_segments ss
        ON b.customer_id = ss.customer_id
    
    GROUP BY 
        b.year,
        b.period,
        b.cbsa_code,
        b.cbsa_name,
        b.channel,
        ss.shopper_type,
        b.store_id,
        b.category_name,
        income_bucket,
        age_bucket
)

SELECT *
FROM final
ORDER BY year, shopper_type, store_id;
