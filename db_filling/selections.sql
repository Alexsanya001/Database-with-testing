--------------------------------------------------PRODUCTS--------------------------------------------------------------
-- Example with function:
select *
from get_products_of_supplier(1, 'EN', 'RON')
LIMIT 5;

-- Example with view:
SELECT product_id, title, price
FROM get_products_by_supplier
WHERE supplier_id = 1
  AND lang_code = 'EN'
  AND currency_code = 'RON';

-----------------------------------------------------AVERAGE------------------------------------------------------------

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


-- Example with function
SELECT *
FROM get_average_price(23, 'CNY');


------------------------------------------------------TITLE-------------------------------------------------------------

-- Product titles ordered by language and id
SELECT *
FROM product_titles
ORDER BY lang_code, product_id;


-- Example with function
SELECT *
FROM get_titles_in_language('RO', 100000, 0);


----------------------------------------------EXPLAIN ANALYZE-----------------------------------------------------------
EXPLAIN ANALYZE
select *
from get_products_of_supplier(1, 'EN', 'RON');

EXPLAIN ANALYZE
SELECT p.id, pt.title, pr.price
from products p
         join product_titles pt on p.id = pt.product_id
         join prices pr on p.id = pr.product_id
where p.supplier_id = 1
  and pr.currency_code = 'RON'
  AND pt.lang_code = 'EN';

EXPLAIN ANALYZE
SELECT product_id, title, price
FROM get_products_by_supplier
WHERE supplier_id = 1
  AND lang_code = 'EN'
  AND currency_code = 'RON';

EXPLAIN ANALYZE
SELECT DISTINCT s.name                  AS company,
                pr.currency_code        AS currency,
                round(AVG(pr.price), 2) AS avg_price
FROM suppliers s
         JOIN
     products p ON s.id = p.supplier_id
         JOIN
     prices pr ON p.id = pr.product_id
GROUP BY s.name, pr.currency_code
ORDER BY s.name;

explain analyze
SELECT *
FROM get_average_price(23, 'CNY');

EXPLAIN ANALYZE
SELECT *
FROM product_titles
ORDER BY lang_code, product_id;

EXPLAIN ANALYZE
SELECT *
FROM get_titles_in_language('RO', 100000, 0);

