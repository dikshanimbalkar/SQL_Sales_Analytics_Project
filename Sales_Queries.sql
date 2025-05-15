-- Years wise total Sales

SELECT 
     YEAR([order_date]),
     sum([sales_amount]) as total_sales,
	 COUNT(distinct customer_key) as total_customer,
	 SUM(quantity) AS total_quantity
      
  FROM [DataWarehouseAnalytics].[gold].[fact_sales]
  where order_date is not null
  group by YEAR([order_date])
  order by YEAR([order_date]);


  -- Month wise total Sales

  SELECT 
     month([order_date]),
     sum([sales_amount]) as total_sales,
	 COUNT(distinct customer_key) as total_customer,
	 SUM(quantity) AS total_quantity
      
  FROM [DataWarehouseAnalytics].[gold].[fact_sales]
  where order_date is not null
  group by month([order_date])
  order by month([order_date]);

-- solve with the help of truncate function

SELECT 
    format(order_date, 'yyyy-MMM') as order_date,
     sum([sales_amount]) as total_sales,
	 COUNT(distinct customer_key) as total_customer,
	 SUM(quantity) AS total_quantity
      
  FROM [DataWarehouseAnalytics].[gold].[fact_sales]
  where order_date is not null
  group by format(order_date, 'yyyy-MMM')
  order by format(order_date, 'yyyy-MMM');

-- calculate the total sales per month
-- and running total of sales over time

with cte as
(
select 
	DATETRUNC(YEAR, order_date) as order_date,
	sum(sales_amount) as total_sales,
	AVG(price) as total_avg
from gold.fact_sales
where order_date is not null
group by DATETRUNC(YEAR, order_date)
) 
select 
order_date,
total_sales,
sum(total_sales) over(order by order_date) as running_total,
AVG(total_avg) over(order by order_date) as moving_avg_price
from cte
order by order_date;

/* Analyze the yearly performance of products by comparing their sales
 to both the avrage sales performance of the product and the previous years sales */


 with yr_product_sales as
 (
 select 
 year(f.order_date) as order_year,
 p.product_name,
 sum(f.sales_amount) as current_sales
 from gold.fact_sales f
 left join gold.dim_products p
 on f.product_key = p.product_key
 where order_date is not null
 group by year(f.order_date), p.product_name
 )
 select 
 order_year,
 product_name,
 current_sales,
 AVG(current_sales) over(partition by product_name) as avg_sales,
 current_sales - AVG(current_sales) over(partition by product_name) as diff_avg,
 case when current_sales - AVG(current_sales) over(partition by product_name) > 0 then 'Above Avg'
	  when current_sales - AVG(current_sales) over(partition by product_name) < 0 then 'Below Avg'
	  else 'Avg'
 end avg_change,
 LAG(current_sales) over(partition by product_name order by order_year) as py_sales,
 current_sales - LAG(current_sales) over(partition by product_name order by order_year) as diff_py,
  case when current_sales - LAG(current_sales) over(partition by product_name order by order_year) > 0 then 'Increment'
	  when current_sales - LAG(current_sales) over(partition by product_name order by order_year) < 0 then 'Loss'
	  else 'No chenge'
 end py_change
 from yr_product_sales;


 -- Which category contribute the most to overall sales?

with category_sales as
(
select 
p.category,
sum(f.sales_amount) as total_sales
from gold.fact_sales f 
left join gold.dim_products p
on f.product_key = p.product_key
group by p.category)
select category,
total_sales,
sum(total_sales) over() overall_sales,
CONCAT(ROUND(cast(total_sales as float) / sum(total_sales) over() * 100, 2), '%') as per_of_total
from category_sales
order by total_sales desc;


 -- Which sub-category contribute the most to overall sales?

with subcategory_sales as
(
select 
p.subcategory,
sum(f.sales_amount) as total_sales
from gold.fact_sales f
left join gold.dim_products p
on f.product_key = p.product_key
where p.category = 'Bikes'
group by p.subcategory)
select subcategory,
total_sales,
sum(total_sales) over() overall_sales,
CONCAT(ROUND(cast(total_sales as float) / sum(total_sales) over() * 100, 2), '%') as per_of_total
from subcategory_sales
order by total_sales desc;

/* Segment products into cost ranges and 
count how many products fall into each segment */

with product_segment as(
select 
product_key,
product_name,
cost,
case 
	when cost < 100 then 'Below 100'
	when cost between 100 and 500 then '100-500'
	when cost between 500 and 1000 then '500-1000'
	else 'Above 1000'
	end cost_range
from gold.dim_products)
select cost_range,
COUNT(product_key) as total_products
from product_segment
group by cost_range;


/* Group customers into three segments based on their spending behavior:
  - VIP: customer with at least 12 months of history and spending more than $5000.
  - Regular:  customer with at least 12 months of history but spending $5000 or less.
  - New: Customer with lifespan less than 12 months.
And Find total number of customers by each group
*/


with customer_spending as
(
select 
c.customer_key,
sum(f.sales_amount) as total_spending,
min(f.order_date) as first_order,
MAX(f.order_date) as last_order,
DATEDIFF (month, min(order_date), max(order_date)) as lifespan
from gold.fact_sales f
left join gold.dim_customers c
on f.customer_key = c.customer_key
group by c.customer_key
)
select customer_segment,
count(customer_key) as total_count
from
(
select
customer_key,
total_spending,
lifespan,
case 
	when lifespan >=12 and total_spending > 5000 then 'VIP'
	when lifespan >=12 and total_spending <= 5000 then 'Regulare'
	else 'New'
end customer_segment
from customer_spending
) t
group by customer_segment
order by total_count desc;

/*
=================================================================================
**** Customer Reports ****
=================================================================================
Highlights:
  1. Gathers essential fields such as names, ages, and transaction details.
  2. Segments customers into categories (VIP, Regular, New) and Age Groups.
  3. Aggregates Customer - level matrix:
		- Total orders
		- total sales
		- total quantity purchased
		- total products 
		- lifespan (in months)
	4. Calculate valuable KPIs:
		- recency (month since last order)
		- average order value
		- average monthly spend
*/

create view gold.report_customers as

with basic_query as(
/*--------------------------------------------------------------------------------
	1. Basic Query: retrive core columns from tables
--------------------------------------------------------------------------------*/
select 
	f.order_number,
	f.product_key,
	f.order_date,
	f.sales_amount,
	f.quantity,
	c.customer_key,
	c.customer_number,
	CONCAT(c.first_name, ' ', c.last_name) as customer_name,
	DATEDIFF(year, c.birthdate, GETDATE()) as age
from gold.fact_sales f
left join gold.dim_customers c
on f.customer_key = c.customer_key
where order_date is not null
),
customer_agg as(
/*----------------------------------------------------------------------------
2) Customer Aggregations: Summarizes key metrics at the customer level
----------------------------------------------------------------------------*/
select 
	customer_key,
	customer_number,
	customer_name,
	age,
	COUNT(distinct order_number) as total_orders,
	sum(sales_amount) as total_sales,
	sum(quantity) as total_quantity,
	COUNT(distinct product_key) as total_products,
	max(order_date) as last_order_date,
	DATEDIFF(month, min(order_date), max(order_date)) as lifespan
from basic_query
group by 
	customer_key,
	customer_number,
	customer_name,
	age
)
select 
	customer_key,
	customer_number,
	customer_name,
	age,
	Case
		when age < 20 then 'Under 20'
		when age between 20 and 29 then '20-29'
		when age between 30 and 39 then '30-39'
		when age between 40 and 49 then '40-49'
		else '50 and Above'
	end age_group,
	case 
		when lifespan >=12 and total_sales > 5000 then 'VIP'
		when lifespan >=12 and total_sales <= 5000 then 'Regulare'
		else 'New'
	end customer_segment,
	last_order_date,
	DATEDIFF(MONTH, last_order_date, getdate()) as recency,
	total_orders,
	total_sales,
	total_quantity,
	total_products,
	lifespan,
	-- Cumpute average order value (AVO)
	case 
		when total_sales = 0 then 0
		else total_sales / total_orders
	end as avg_order_value,
	-- Compute average monthly spend
	case
		when lifespan = 0 then total_sales
		else total_sales / lifespan
	end avg_monthly_spend
from customer_agg;

select * from gold.report_customers;


/*
=================================================================================
**** Product Reports ****
=================================================================================
Purpose:
   	- This report consolidates key customer metrics and behaviours.

Highlights:
  1. Gathers essential fields such as Product_name, category, subcategory and cost.
  2. Segments products by revenue to identify high-performers, Mid_range, or Low-Performance.
  3. Aggregates Product-level metrics:
		- Total orders
		- total sales
		- total quantity sold
		- total customers(unique) 
		- lifespan (in months)
	4. Calculate valuable KPIs:
		- recency (month since last sale)
		- average order revenue
		- average monthly revenue
*/

create view gold.product_report as

with base_product as(
/*---------------------------------------------------------------------------
1) Base Query: Retrieves core columns from fact_sales and dim_products
---------------------------------------------------------------------------*/
select 
	f.order_number,
	f.order_date,
	f.customer_key,
	f.sales_amount,
	f.quantity,
	p.product_key,
	p.product_name,
	p.category,
	p.subcategory,
	p.cost
from gold.fact_sales f
left join gold.dim_products p
on f.product_key = p.product_key
where order_date is not null
),
 product_aggregations as(
/*---------------------------------------------------------------------------
2) Product Aggregations: Summarizes key metrics at the product level
---------------------------------------------------------------------------*/
select 
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	COUNT(distinct order_number) as total_orders,
	COUNT(distinct customer_key) as total_customer,
	SUM(sales_amount) as total_sales,
	SUM(quantity) as total_quantity,
	DATEDIFF(month, MIN(order_date), max(order_date)) as lifespan,
	MAX(order_date) as last_sale_date,
	round(AVG(cast(sales_amount as float) / nullif(quantity, 0)), 2) as avg_selling_price
from base_product
group by
	product_key,
	product_name,
	category,
	subcategory,
	cost
)
/*---------------------------------------------------------------------------
  3) Final Query: Combines all product results into one output
---------------------------------------------------------------------------*/
select
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	last_sale_date,
	DATEDIFF(month, last_sale_date, GETDATE()) as recency_in_months,
		CASE
		WHEN total_sales > 50000 THEN 'High-Performer'
		WHEN total_sales >= 10000 THEN 'Mid-Range'
		ELSE 'Low-Performer'
	END AS product_segment,
	lifespan,
	total_orders,
	total_customer,
	total_sales,
	total_quantity, 
	avg_selling_price,
	-- Average Order Revenue (AOR)
	CASE 
		WHEN total_orders = 0 THEN 0
		ELSE total_sales / total_orders
	END AS avg_order_revenue,

	-- Average Monthly Revenue
	CASE
		WHEN lifespan = 0 THEN total_sales
		ELSE total_sales / lifespan
	END AS avg_monthly_revenue

from product_aggregations;

select * from gold.product_report