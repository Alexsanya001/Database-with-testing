-- Average prices in different countries in different currencies
SELECT c.name                  AS country,
       pr.currency_code        AS currency,
       round(AVG(pr.price), 2) AS avg_price
FROM suppliers s
         JOIN
     products p ON s.id = p.supplier_id
         JOIN
     prices pr ON p.id = pr.product_id
         JOIN
     cities ct ON ct.id = s.city_id
         JOIN
     countries c ON ct.country_id = c.id
GROUP BY c.name, pr.currency_code
ORDER BY c.name;
