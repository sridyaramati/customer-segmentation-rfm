/*
=================================================================
Data Ingestion and Staging (Raw CSV -> Staging Table)
=================================================================
Script Purpose:
	This script performs the initial ETL(Extract, Transform, Load) process to
    ingest raw transaction data from a CSV source file into a staging table within the database, 
    applying initial cleaning before downstream RFM segmentation.
    
Actions Performed: 
	- Creates the staging table schema (if it does not already exist).
    - Loads raw transaction data from the source CSV file into 'raw_transactions' table
    - Performs initial data cleaning and standardizes data types into staging table: 'staged_transactions'
======================================================================
*/


-- Bulk upload of the dataset  
LOAD DATA LOCAL INFILE 'C:/Users/19178/Desktop/Data Analyst Portfolio Projects/RFM Project/OnlineRetail.csv'  
INTO TABLE raw_transactions 
CHARACTER SET latin1 
FIELDS TERMINATED BY ','  
ENCLOSED BY '"' 
LINES TERMINATED BY '\n' 
IGNORE 1 LINES 
(InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, @v_customer_id, Country) 
SET CustomerID = NULLIF(TRIM(@v_customer_id), '');

-- Check if data loaded properly into the table
SELECT * FROM raw_transactions LIMIT 5;

-- Creating a Staged table to perform data cleaning 

DROP TABLE IF EXISTS staged_transactions;
CREATE TABLE staged_transactions AS
SELECT 
    InvoiceNo,
    StockCode,
    TRIM(Description) AS Description, -- Cleans up any messy trailing whitespaces
    Quantity,
    STR_TO_DATE(InvoiceDate, '%m/%d/%Y %H:%i') AS InvoiceDateTime, -- Official SQL DateTime conversion
    UnitPrice,
    (Quantity * UnitPrice) AS TotalRevenue, -- Pre-calculates line-item revenue
    CAST(CustomerID AS UNSIGNED) AS CustomerID, -- Converts the text column to a clean integer ID
    Country
FROM raw_transactions
WHERE CustomerID IS NOT NULL
  AND UnitPrice > 0
  AND Quantity > 0
  AND StockCode NOT REGEXP '^[A-Za-z]+$';
  
  -- Check the quality after initial cleaning 
  SELECT COUNT(*) as clean_row_count FROM staged_transactions;
  -- 396482 rows
  
  -- Auditing the rows if the data deleted doesn't have valid or useful data 
  SELECT 
  COUNT(*) as total_rows,
  SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) as customer_id_null_rows,
  SUM(CASE WHEN Quantity <=0 THEN 1 ELSE 0 END) as quantity_negative_rows,
  SUM(CASE WHEN UnitPrice<=0 THEN 1 ELSE 0 END) as unit_price_negative_rows,
  SUM(CASE WHEN StockCode REGEXP '^[A-Za-z]+$' THEN 1 ELSE 0 END) as admin_codes_rows
  FROM raw_transactions;
  
  
  -- Checking if any data is valid in Quantity < 0, most of the data is cancelled orders or returned 
  SELECT DISTINCT InvoiceNo, Description, CustomerID FROM raw_transactions 
  WHERE Quantity <=0;
  
  
  -- Checking if data is dropped in Stock code for admin charges and shipping costs
  SELECT DISTINCT StockCode, Description, CustomerID FROM raw_transactions
  WHERE StockCode REGEXP '^[A-Za-z]+$'; 
