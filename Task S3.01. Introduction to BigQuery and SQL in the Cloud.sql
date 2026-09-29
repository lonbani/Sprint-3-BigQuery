-- creat transaction table in sprit_3 bronze
create external table `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw`
(
 id string,
 card_id string,
 business_id string,
 timestamp string,
amount string,
declined string,
product_ids string,
user_id string,
lat string,
longitude string
)
options
(
  format='csv',
  uris=['gs://bootcamp-data-analytics-public/ERP/transactions.csv'],
  field_delimiter=';',
  skip_leading_rows=1
);


-- creat companies table in sprit_3 bronze
create external table `sprint3-analytics-mahnaz.sprint3_bronze.companies_raw`
(
company_id  string,
company_name string,
phone string,
email string,
country string,
website string
)
options
(
  format='csv',
  uris=['gs://bootcamp-data-analytics-public/ERP/companies.csv'],
  field_delimiter=',',
  skip_leading_rows=1
);



-- creat american_users_raw table in sprit_3 bronze
create external table `sprint3-analytics-mahnaz.sprint3_bronze.american_users_raw`
(
id string,
name string,
surname string,
phone string,
email string,
birth_date string,
country string,
city string,
postal_code string,
address string
)
options
(
  format='csv',
  uris=['gs://bootcamp-data-analytics-public/CRM/american_users.csv'],
  field_delimiter=',',
  skip_leading_rows=1
);



-- creat european_users_raw table in sprit_3 bronze
create external table `sprint3-analytics-mahnaz.sprint3_bronze.european_users_raw`
(
id string,
name string,
surname string,
phone string,
email string,
birth_date string,
country string,
city string,
postal_code string,
address string
)
options
(
  format='csv',
  uris=['gs://bootcamp-data-analytics-public/CRM/european_users.csv'],
  field_delimiter=',',
  skip_leading_rows=1
);


-- creat credit_cards_raw table in sprit_3 bronze
create external table `sprint3-analytics-mahnaz.sprint3_bronze.credit_cards_raw`
(
  id string,
  user_id string,
  iban string,
  pan string,
  pin string,
  cvv string,
  track1 string,
  track2 string,
  expiring_date string
)
options
(
  format='csv',
  uris=['gs://bootcamp-data-analytics-public/CRM/credit_cards.csv'],
  field_delimiter=',',
  skip_leading_rows=1
);


-- Exercise 3: Uploading Local Data
-- The Products table
--done


-- Exercise 4: Architecture and Performance. Data Materialization (AI Assisted)
-- a) AI Assisted
CREATE OR REPLACE TABLE sprint3_bronze.transactions_raw_native AS
SELECT *
FROM `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw`;


-- b) Cost Audit
--Design a test to compare the cost of reading a single column (ex: id) in the external table vs. the native table. Use Bytes Processed and Bytes Billed to make the comparison.

-- How much does the query "weigh" transactions_raw?
select id
from `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw`;

-- How much does the same query "weigh" in transactions_raw_native?
select id
from `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw_native`;

-- c)c) The danger of the LIMIT
-- LIMIT 10 on transactions_raw_native
select* 
from `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw_native`
limit 10;
--  Without LIMIT 10 on transactions_raw_native
select* 
from `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw_native`;
-- LIMIT 10 on transactions_raw
select *
from `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw`
limit 10;
--  Without LIMIT 10 on transactions_raw
select* 
from `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw`;

-- Exercise 5: Syntax Adaptation (Reporting)
-- Your boss wants to know what the 5 most profitable days of 2021 were .
select date(safe_cast(timestamp as timestamp)) AS dates,
       sum (safe_cast(amount AS float64)) AS total_sell
from `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw`
where extract(year from safe_cast(timestamp as timestamp)) = 2021 
group by  dates
order by total_sell desc
limit 5; 


-- Exercise 6: Complex Queries
-- We need a report that crosses data.
--List the name, country and date of transactions carried out by companies
-- that made operations between 100 and 200 euros on any of these dates: 04-29-2015, 07-20-2018 or 04-29-2015, 07-20-2018.

select c.company_name, c.country,
date(safe_cast(t.timestamp as timestamp)) AS dates,
safe_cast(t.amount AS float64) AS sell 
from `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw` AS t
join `sprint3-analytics-mahnaz.sprint3_bronze.companies_raw` AS c
     on t.business_id=c.company_id
where date(safe_cast(t.timestamp as timestamp)) in ( DATE '2015-04-29', DATE '2018-07-20', DATE '2024-03-13')
and
safe_cast(t.amount as float64) between 100 and 200; 



--Level 2: Cleaning and Transformation (ELT)
-- Exercise 1: Product Cleaning (Data Quality)
-- sprint3_silver.products_cleanmeets these quality rules:

--  Name Standardization : The original id column is ambiguous;
-- rename it to product_id. Simplify the product_name column to name.
-- Clean IDs : The warehouse_id field has the old format "WH-4". Remove the "WH-" prefix and convert the value to an integer (INT64).
-- Price Guarantee : Make sure price is a number (FLOAT64), without currency symbols.
-- Other columns : Keep the weight field as is.

create or replace table `sprint3-analytics-mahnaz.sprint3_silver.products_clean` AS
select 
id AS product_id,
product_name AS name,
safe_cast(price as float64) price,
colour,
weight,
safe_cast(replace(warehouse_id, 'WH-', '') as int64) AS warehouse_id,
category,
brand,
cost,
launch_date
from `sprint3-analytics-mahnaz.sprint3_bronze.products_raw`;

-- Exercise 2: Creating Net Transactions (Silver Layer)
-- We will create the final table sprint3_silver.transactions_cleanthat guarantees the following.

-- Naming Standardization : The original id column is ambiguous; rename it to transaction_id. 
-- » Robustness in Amounts : Use SAFE_CAST on the amount field. If it fails, replace it with 0 (using IFNULL).
--» Real Dates : Converts the timestamp field (which is STRING) to real TIMESTAMP type.
--» Coordinates : Ensure that lat and longitude are FLOAT64 (use SAFE_CAST for safety).
--» Breakdown of Products: Transform the text string product_ids into an ARRAY of integers .
 --» Rest of the fields : Keep them the same.
 create or replace table `sprint3-analytics-mahnaz.sprint3_silver.transactions_clean` AS
 select 
id as transaction_id,
card_id,
business_id,
safe_cast(timestamp AS timestamp) AS timestamp,
ifnull (safe_cast(amount as float64), 0) AS amount,
declined,
array(
  select safe_cast(trim(product_id) as int64)
  from unnest(split (product_ids, ',')) AS product_id
) as product_ids,
user_id,
safe_cast(lat as float64) as lat,
safe_cast(longitude as float64) as longitude
from `sprint3-analytics-mahnaz.sprint3_bronze.transactions_raw`;

-- Exercise 3: User Unification (UNION)
--We have users fragmented by region.
--Create the table sprint3_silver.users_combined. Use UNION ALLto unify users from the US and Europe into a single --master list. Add a calculated column origin to know where they come from.
--» Name Standardization : The original id column is ambiguous; rename it to user_id.
create or replace table `sprint3-analytics-mahnaz.sprint3_silver.users_combined` AS
select 
id AS user_id,
name,
surname,
phone,
email,
birth_date,
country,
city,
postal_code,
address,
'USA' as origin
from `sprint3-analytics-mahnaz.sprint3_bronze.american_users_raw`
union all
select 
id AS user_id,
name,
surname,
phone,
email,
birth_date,
country,
city,
postal_code,
address,
'EU' as origin
from `sprint3-analytics-mahnaz.sprint3_bronze.european_users_raw`;

--Exercise 4: Materialization of Companies and Credit Cards
-- » 1. Create the table sprint3_silver.companies_clean. Copy the data as is, but make sure it is a native BigQuery table (not an external view).
-- If necessary, rename the id as appropriate.
create or replace table `sprint3-analytics-mahnaz.sprint3_silver.companies_clean` AS
select *
from `sprint3-analytics-mahnaz.sprint3_bronze.companies_raw`;

--» 2. Create the table sprint3_silver.credit_cards_clean. Copy the data as is, but make sure it is a native BigQuery table (not an external view).

create or replace table `sprint3-analytics-mahnaz.sprint3_silver.credit_cards_clean` AS
select * except(id),
         id AS card_id
from `sprint3-analytics-mahnaz.sprint3_bronze.credit_cards_raw`; 


-- Level 3: Data Presentation and View Creation

-- Exercise 1: The Marketing View (Business Logic)
--Create a named view sprint3_gold.v_marketing_kpisthat displays the following information for each company:
-- » Company name, Phone and Country (source: companies_clean).
-- » Average purchase (AVG(amount) of transactions_clean).
-- » Customer Classification (Logic) :
-- Create a calculated column called client_tier.
-- If the average purchase is above €260 , label it as "Premium" .
-- If equal or lower, label as "Standard" .

create or replace view `sprint3-analytics-mahnaz.sprint3_gold.v_marketing_kpis` AS
select c.company_name,
       c.phone,
       c.country,
       round(avg(t.amount), 2) AS avarage_sell,
       case when avg(t.amount)> 260 then 'Premium'
            else 'Standard'
            end as client_tier
from `sprint3-analytics-mahnaz.sprint3_silver.companies_clean` AS c
join `sprint3-analytics-mahnaz.sprint3_silver.transactions_clean` AS t
on c.company_id=t.business_id
group by c.company_name,c.phone,c.country;

select *
from `sprint3-analytics-mahnaz.sprint3_gold.v_marketing_kpis`
order by CASE
        WHEN client_tier = 'Premium' THEN 1
        ELSE 2
    END,
    avarage_sell DESC; 

-- Exercise 2: Product Ranking (The Power of Arrays)
-- Create the table sprint3_gold.product_sales_rankingthat contains the complete inventory of products and how many times each has been sold.
-- » Product Detail : Must include product_id, name, price and color (they come from the products_clean table).
-- » Business Metric : A new total_sold column that counts how many times this product appears in transactions.
-- » Integrity : All products must appear, even those with 0 sales (they may need to be discontinued).
--» In transactions_clean, the products are "encapsulated" within an Array for each transaction.
-- » First you will need to "flatten" the transactions table using UNNEST(product_ids) to be able to count the products individually.
-- » Then, do a LEFT JOIN starting with the products table so you don't lose those that have never been sold.

create or replace table `sprint3-analytics-mahnaz.sprint3_gold.product_sales_ranking` AS
with sales AS 
(
  select product_id, count(transaction_id ) AS total_sold
  from `sprint3-analytics-mahnaz.sprint3_silver.transactions_clean`
  cross join unnest(product_ids) AS product_id
  group by product_id
)
select p.product_id,p.name, p.price, p.colour, ifnull(s.total_sold,0) AS total_sold
from `sprint3-analytics-mahnaz.sprint3_silver.products_clean` AS p
left join sales AS s
on p.product_id=s.product_id;
 
 select *
 from `sprint3-analytics-mahnaz.sprint3_gold.product_sales_ranking`
 order by total_sold desc;




































