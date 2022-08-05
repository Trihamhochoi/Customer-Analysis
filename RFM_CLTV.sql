DROP VIEW IF EXISTS dbo.RFM_Segment
GO 

CREATE VIEW RFM_Segment
AS WITH 
Rfm_raw AS(
	SELECT
	CustomerID,
	datediff(DAY,Max(OrderDate),'2015-01-01') as Recency,
	COUNT(*) Frequency,
	SUM(TotalDue) Monetary
	FROM Sales.SalesOrderHeader
	GROUP BY CustomerID)

,calc_rfm AS(
	SELECT
	rfm_raw.*, 
	NTILE(5) OVER (ORDER BY Recency desc) AS R_rank,
	NTILE(5) OVER (ORDER BY Frequency) AS F_rank,
	NTILE(5) OVER (ORDER BY Monetary) AS M_rank,
	CONVERT(NVARCHAR(1),
	NTILE(5) OVER (ORDER BY Recency desc))+CONVERT(NVARCHAR(1),NTILE(5) OVER (ORDER BY Frequency))+convert(nvarchar(1),NTILE(5) OVER (ORDER BY Monetary)) 
	AS RFM_totalrank
	FROM Rfm_raw)

SELECT 
	*,
	(CASE
		WHEN RFM_totalrank LIKE '[1-2][1-2][1-2]'THEN 'Lost'
		WHEN RFM_totalrank LIKE '[1-2][1-2][3-4]' or RFM_totalrank LIKE '[1-2][3-5][1-2]' THEN 'Hibernating'
		WHEN RFM_totalrank LIKE '[1-2][3-5][3-4]' THEN 'At risk'
		WHEN RFM_totalrank LIKE '[1-2][1-5][5]' THEN 'Can not lose them'
		WHEN RFM_totalrank LIKE '[3][1-2][1-2]' THEN 'About to sleep'
		WHEN RFM_totalrank LIKE '[3][1-5][3-4]' or RFM_totalrank LIKE '[3][1-5][5]' THEN 'Need attention'
		WHEN RFM_totalrank LIKE '[4-5][1-2][1-2]' or RFM_totalrank LIKE '[3][3-5][1-2]' THEN 'Promising'
		WHEN RFM_totalrank LIKE '[4-5][1-2][3-5]' or RFM_totalrank LIKE '[4-5][3-5][1-4]' THEN 'Potential loyalist'
		WHEN RFM_totalrank LIKE '[4][3-5][5]' THEN 'Loyal customers'
		WHEN RFM_totalrank LIKE '[4-5][1-5][1-3]' THEN 'Recent customers'
		WHEN RFM_totalrank LIKE '5[3-5][5]' THEN 'Champions'
		END ) AS RFM_segment 
FROM calc_rfm
go

SELECT * FROM dbo.RFM_Segment
ORDER BY R_rank, M_rank desc

-- Calculate CLTV Customer Lifetime Value
--Average monthly revenue per user ARPU
 DECLARE @mindate date= (SELECT MIN(OrderDate) FROM Sales.SalesOrderHeader)
 DECLARE @ARPU FLOAT, @churn_rate FLOAT;

WITH 
monthly_revenue AS 
 	(SELECT
	CustomerID, DATEDIFF(MONTH,@mindate, OrderDate) AS visit_month,
	SUM(TotalDue) AS revenue
	FROM Sales.SalesOrderHeader
	GROUP BY CustomerID, DATEDIFF(MONTH,@mindate, OrderDate))

-- revenue per user in  month

,ARPU_table AS 
	(SELECT 
	visit_month, AVG(revenue) AS ARPU
	FROM monthly_revenue
	GROUP BY visit_month)

SELECT @ARPU =  AVG(ARPU) FROM ARPU_table;

------------------------------------
 WITH 
monthly_visit AS
 (SELECT
	CustomerID, DATEDIFF(MONTH,@mindate, OrderDate) AS visit_month
FROM Sales.SalesOrderHeader
GROUP BY CustomerID, DATEDIFF(MONTH,@mindate, OrderDate))

	,churn_retain AS(
	SELECT 
	past_month.CustomerID, 
	past_month.visit_month+1 current_month,
	CASE 
		WHEN current_month.CustomerID IS NULL 
		THEN 'churn' 
		ELSE 'retained' --continue buy product
	END AS type
FROM monthly_visit past_month LEFT JOIN monthly_visit current_month
ON past_month.CustomerID = current_month.CustomerID 
AND current_month.visit_month = past_month.visit_month+1)

	,churn_rate AS (
	SELECT 
	current_month, 
	SUM(CASE type WHEN 'churn' THEN 1 ELSE 0 end)
	/CONVERT(FLOAT,COUNT(customerID)) AS churn_rate
FROM churn_retain
GROUP BY current_month)

SELECT @churn_rate = AVG(churn_rate) FROM churn_rate

-- CLTV
SELECT @ARPU/@churn_rate AS CLTV
