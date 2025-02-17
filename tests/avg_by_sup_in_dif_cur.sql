-- Average cost of products of some supplier in different currencies
SELECT s.name                  AS company,
       pr.currency_code        AS currency,
       round(AVG(pr.price), 2) AS avg_price
FROM suppliers s
         JOIN
     products p ON s.id = p.supplier_id
         JOIN
     prices pr ON p.id = pr.product_id
GROUP BY s.name, pr.currency_code
ORDER BY s.name;
