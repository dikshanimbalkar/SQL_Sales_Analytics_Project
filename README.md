# Sales Analytics Project

📁 Dataset Description
- **fact_sales**: Contains transaction-level sales records.
- **dim_customers**: Contains demographic information for customers.
- **dim_products**: Contains details of products including cost, category, and subcategory.

- 🧾 Key SQL Concepts Used
- Joins and Aggregations
- Common Table Expressions (CTEs)
- Window Functions (e.g., `LAG`, `SUM OVER`, `AVG OVER`)
- Views for Reporting
- Case Statements for Segmentation
- Time Series and Date Truncation

- 📊 Views Created
- `gold.report_customers`: Customer-level report with age groups, segments, and KPIs.
- `gold.product_report`: Product-level report with performance segments and revenue metrics.

🔍 Sample Insights
- Bike sub-category drives the highest revenue.
- VIP customers make up a small portion but contribute the most to total sales.
- Products with cost > $1000 are top performers in terms of revenue.
