/*
============================================================
RFM Segmentation (Staging -> Customer Segments)
============================================================

Script Purpose:
	This script performs RFM (Recency, Frequency, Monetary) analysis on 
    cleansed transaction data from staging table, scoring and classifying each customer
    into a named business segment.
    
Actions Performed:
	- Aggregates transaction-level grain data into per-customer totals:
		- Recency: days since each customer's most recent purchase
        - Frequency: count of distinct purchase invoice per customer
        - Monetary: total revenue generated per customer
	- Sets a dynamic anchor date (MAX(invoice_date)+1 day) so recency is calculated 
      relative to most recent activity in dataset.
	- Applies NTILE(5) window function to assign each customer a quintile score (1-5) for RFM metrics.
    - Combines 3 quintile scores into a single RFM score per customer.
    - Maps RFM score combinations to 8 business-defined segments.
    
Dependencies:
	- Requires the staging table from data_ingestion_staging.sql script as its input.
=====================================================================================

*/

-- Get last invoice date from the dataset
SELECT MAX(InvoiceDateTime) as latest_transaction_date 
FROM staged_transactions;

-- Create RFM metrics table groupig by customer id
DROP TABLE IF EXISTS customer_rfm_summary;
CREATE TABLE customer_rfm_summary AS
SELECT 
    CustomerID,
    DATEDIFF('2011-12-10', MAX(InvoiceDateTime)) AS recency, -- Days since last purchase
    COUNT(DISTINCT InvoiceNo) AS frequency,                 -- Total unique shopping trips
    ROUND(SUM(TotalRevenue), 2) AS monetary                  -- Total net spend
FROM staged_transactions
GROUP BY CustomerID;

-- Check the quality of rows 
SELECT * FROM customer_rfm_summary LIMIT 5;

SELECT 
MAX(recency), MIN(recency),
MAX(frequency), MIN(frequency),
MAX(monetary), MIN(monetary)
FROM customer_rfm_summary;

-- Calculate the recency percentile cutoffs
WITH recency_p AS (
SELECT
CustomerID,
recency,
NTILE(5) OVER(ORDER BY recency) recency_bucket
FROM customer_rfm_summary
)

SELECT 
MAX(CASE WHEN recency_bucket = 1 THEN recency END) as p20,
MAX(CASE WHEN recency_bucket = 2 THEN recency END) as p40,
MAX(CASE WHEN recency_bucket = 3 THEN recency END) as p60,
MAX(CASE WHEN recency_bucket = 4 THEN recency END) as p80
FROM recency_p;

-- Assigning the Individual R, F, and M Scores and putting them in a new table 
DROP TABLE IF EXISTS customer_rfm_scores;
CREATE TABLE customer_rfm_scores AS 
SELECT
CustomerID,
recency,
frequency,
monetary,
NTILE(5) OVER(ORDER BY recency DESC) recency_score,
NTILE(5) OVER(ORDER BY frequency) frequency_score,
NTILE(5) OVER(ORDER BY monetary) monetary_score
FROM customer_rfm_summary;

-- Generating 3 digit RFM cell and consolidated score

SELECT * FROM customer_rfm_scores;

SELECT 
CustomerID, 
recency_score,
frequency_score,
monetary_score,
CONCAT(CAST(recency_score AS CHAR), CAST(frequency_score AS CHAR), CAST(monetary_score AS CHAR)) as rfm_cell,
(recency_score + frequency_score + monetary_score) as rfm_total_score
FROM customer_rfm_scores
;

-- Create a table to store these values
DROP TABLE IF EXISTS customer_rfm_segments;
CREATE TABLE customer_rfm_segments AS 
SELECT 
CustomerID, 
recency_score,
frequency_score,
monetary_score,
CONCAT(CAST(recency_score AS CHAR), CAST(frequency_score AS CHAR), CAST(monetary_score AS CHAR)) as rfm_cell,
(recency_score + frequency_score + monetary_score) as rfm_total_score
FROM customer_rfm_scores;

SELECT * FROM customer_rfm_segments LIMIT 5;

-- Final Business Segmentation Matrix
SELECT AVG(recency_score), AVG(frequency_score), AVG(monetary_score) FROM customer_rfm_segments;
SELECT 
rfm_cell,
rfm_total_score,
CASE WHEN recency_score IN (4,5) AND frequency_score IN (4,5) AND monetary_score IN (4,5) THEN 'Champions' 
	 WHEN recency_score IN (1,2) AND (frequency_score IN (4,5) OR monetary_score IN (4,5)) THEN 'At Risk//Cant Lose Them' 
     WHEN recency_score IN (4,5) AND frequency_score = 1  THEN 'New Customers'
     WHEN recency_score = 1 AND frequency_score = 1 AND monetary_score = 1 THEN 'Lost or Hibernating' 
     WHEN recency_score < 3 AND (frequency_score < 3 OR monetary_score < 3) THEN 'About To Sleep' 
     WHEN frequency_score IN (4,5) THEN 'Loyal Customers'
     WHEN recency_score IN (4,5) AND frequency_score = 3 THEN 'Potential Loyalists' 
     ELSE 'General or Others'
END as business_segment
FROM customer_rfm_segments;

-- Create a table with above output as final segmentation 
DROP TABLE IF EXISTS customer_final_segmentation;
CREATE TABLE customer_final_segmentation AS
SELECT 
CustomerID,
recency_score,
frequency_score,
monetary_score,
rfm_cell,
rfm_total_score,
CASE WHEN recency_score IN (4,5) AND frequency_score IN (4,5) AND monetary_score IN (4,5) THEN 'Champions' 
	 WHEN recency_score IN (1,2) AND (frequency_score IN (4,5) OR monetary_score IN (4,5)) THEN 'At Risk//Cant Lose Them' 
     WHEN recency_score IN (4,5) AND frequency_score = 1  THEN 'New Customers'
     WHEN recency_score = 1 AND frequency_score = 1 AND monetary_score = 1 THEN 'Lost or Hibernating' 
     WHEN recency_score < 3 AND (frequency_score < 3 OR monetary_score < 3) THEN 'About To Sleep' 
     WHEN frequency_score IN (4,5) THEN 'Loyal Customers'
     WHEN recency_score IN (4,5) AND frequency_score = 3 THEN 'Potential Loyalists' 
     ELSE 'General or Others'
END as business_segment
FROM customer_rfm_segments;

-- Portfolio Health and Macro Segmentation Distribution
SELECT
business_segment,
COUNT(*) as customer_count,
ROUND((COUNT(*)/4335) * 100, 2) as percentage_of_total
FROM customer_final_segmentation
GROUP BY business_segment
ORDER BY customer_count DESC;




