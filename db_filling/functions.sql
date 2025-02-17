-- Function for getting products of a supplier by suppliers id
CREATE OR REPLACE FUNCTION get_products_of_supplier(sup_id INT, lang CHAR(2), currency CHAR(3))
RETURNS TABLE (id BIGINT, title TEXT, price NUMERIC(10, 2)) AS
$$
BEGIN
    RETURN QUERY
    SELECT p.id AS product_id, pt.title, pr.price
    FROM products p
        JOIN product_titles pt ON p.id = pt.product_id
        JOIN prices pr ON p.id = pr.product_id
    WHERE p.supplier_id = sup_id
      AND lang_code = lang
      AND currency_code = currency;
END;
$$ LANGUAGE plpgsql;


-- View for getting products by supplier
CREATE OR REPLACE VIEW get_products_by_supplier AS
SELECT p.id AS product_id, p.supplier_id, pt.lang_code, pt.title, pr.currency_code, pr.price
FROM products p
         JOIN product_titles pt ON p.id = pt.product_id
         JOIN prices pr ON p.id = pr.product_id;


-- Function for getting average price by supplier and currency
CREATE OR REPLACE FUNCTION get_average_price(sup_id INT, currency CHAR(3))
    RETURNS TABLE
            (
                company   TEXT,
                avg_price NUMERIC(10, 2)
            )
AS
$$
BEGIN
    RETURN QUERY
        SELECT s.name                  AS company,
               round(AVG(pr.price), 2) AS avg
        FROM suppliers s
                 JOIN
             products p ON s.id = p.supplier_id
                 JOIN
             prices pr ON p.id = pr.product_id
        WHERE p.supplier_id = sup_id
          AND pr.currency_code = currency
        GROUP BY s.name, pr.currency_code
        ORDER BY s.name;
END;
$$
LANGUAGE plpgsql;
-- Function for getting titles in some language with limit and offset
CREATE OR REPLACE FUNCTION get_titles_in_language(lang CHAR(2), "limit" INT, "offset" INT)
    RETURNS TABLE
            (
                title TEXT
            )
AS
$$
BEGIN
    RETURN QUERY
        SELECT pt.title
        FROM product_titles pt
        WHERE lang_code = lang
        LIMIT "limit" OFFSET "offset";
END;
$$
LANGUAGE plpgsql;
-- Function for inserting new supplier (city check may be redundant) returns id of new supplier
CREATE OR REPLACE FUNCTION add_supplier(company TEXT, address TEXT, city TEXT, country TEXT)
    RETURNS INT AS
$$
DECLARE
    new_supplier_id INT;
BEGIN
    WITH new_city AS (
        INSERT INTO cities (name, country_id)
            SELECT city,
                   (SELECT id FROM countries co WHERE co.name = country)
            WHERE NOT EXISTS (SELECT 1
                              FROM cities c
                              WHERE c.name = city
                                AND c.country_id = (SELECT id FROM countries co WHERE co.name = country))
            RETURNING id)
    INSERT
    INTO suppliers (name, street_address, city_id)
    SELECT company,
           address,
           COALESCE(
                   (SELECT c.id
                    FROM cities c
                    WHERE c.name = city
                      AND country_id = (SELECT co.id FROM countries co WHERE co.name = country)),
                   (SELECT id FROM new_city)
           )
    RETURNING id INTO new_supplier_id;
    RETURN new_supplier_id;
END;
$$
LANGUAGE plpgsql;
