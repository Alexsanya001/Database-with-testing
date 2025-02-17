-- Temp table for copying suppliers from file
CREATE TEMP TABLE suppliers_temp
(
    name           TEXT,
    street_address TEXT,
    city           TEXT,
    country        TEXT
);


-- Copying suppliers
COPY suppliers_temp (name, street_address, city, country)
    FROM '/data/suppliers.csv'
    DELIMITER ','
    CSV HEADER
    QUOTE '"';


-- Inserting countries
INSERT INTO countries (name)
SELECT DISTINCT country
FROM suppliers_temp
WHERE country IS NOT NULL;


-- Inserting cities
INSERT INTO cities (name, country_id)
SELECT DISTINCT city, c.id
FROM suppliers_temp st
         JOIN countries c ON st.country = c.name
WHERE st.city IS NOT NULL;


-- Inserting suppliers
INSERT INTO suppliers (name, street_address, city_id)
SELECT st.name, st.street_address, c.id
FROM suppliers_temp st
         JOIN cities c ON st.city = c.name;


-- Deleting temp table with suppliers
DROP TABLE suppliers_temp;


-- Temp table for products
CREATE TEMP TABLE temp_products
(
    nameEN   TEXT,
    nameFR   TEXT,
    nameDE   TEXT,
    nameCN   TEXT,
    nameRO   TEXT,
    priceUSD NUMERIC(10, 2),
    priceEUR NUMERIC(10, 2),
    priceCNY NUMERIC(10, 2),
    priceRON NUMERIC(10, 2),
    supId    INT
);

-- Copying data from file to temp table
COPY temp_products (nameEN, nameFR, nameDE, nameCN, nameRO, priceUSD, priceEUR, priceCNY, priceRON, supId)
    FROM '/data/products.csv'
    DELIMITER ','
    CSV HEADER
    QUOTE '"';


-- Code block for inserting products from temp table
DO
$$
    DECLARE
        rec            RECORD;
        new_product_id BIGINT;
    BEGIN
        FOR rec IN SELECT * FROM temp_products
            LOOP
                INSERT INTO products (supplier_id)
                VALUES (rec.supId)
                RETURNING id INTO new_product_id;

                INSERT INTO product_titles (product_id, lang_code, title)
                VALUES (new_product_id, 'EN', rec.nameEN),
                       (new_product_id, 'FR', rec.nameFR),
                       (new_product_id, 'DE', rec.nameDE),
                       (new_product_id, 'CN', rec.nameCN),
                       (new_product_id, 'RO', rec.nameRO);

                INSERT INTO prices (product_id, currency_code, price)
                VALUES (new_product_id, 'USD', rec.priceUSD),
                       (new_product_id, 'EUR', rec.priceEUR),
                       (new_product_id, 'CNY', rec.priceCNY),
                       (new_product_id, 'RON', rec.priceRON);
            END LOOP;
    END
$$;


-- Deleting of temp table
DROP TABLE temp_products;
