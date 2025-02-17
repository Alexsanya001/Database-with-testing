-- Countries (without duplicates)
CREATE TABLE IF NOT EXISTS countries
(
    id   SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

-- Cities (can be selected/grouped by country, without duplicates of country)
CREATE TABLE IF NOT EXISTS cities
(
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    country_id INT REFERENCES countries(id) ON DELETE CASCADE
);

-- Suppliers (without duplicated cities/countries - id's only)
CREATE TABLE IF NOT EXISTS suppliers
(
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    street_address TEXT,
    city_id INT REFERENCES cities(id)
);

-- Products (without duplicates)
CREATE TABLE IF NOT EXISTS products
(
    id          BIGSERIAL PRIMARY KEY,
    supplier_id INT REFERENCES suppliers (id) ON DELETE CASCADE
);

--Product titles in different languages
CREATE TABLE IF NOT EXISTS product_titles
(
    product_id BIGINT REFERENCES products (id) ON DELETE CASCADE,
    lang_code  CHAR(2) NOT NULL CHECK ( char_length(lang_code) = 2),
    title      TEXT    NOT NULL,
    PRIMARY KEY (product_id, lang_code)
);

--Prices in different currencies
CREATE TABLE IF NOT EXISTS prices
(
    product_id    BIGINT REFERENCES products (id) ON DELETE CASCADE,
    currency_code CHAR(3),
    price         NUMERIC(10, 2),
    PRIMARY KEY (product_id, currency_code)
);

CREATE INDEX idx_products_supplier_id ON products (supplier_id);

CREATE INDEX idx_cities_country_id ON cities (country_id);

CREATE INDEX idx_suppliers_city_id ON suppliers (city_id);

CREATE INDEX idx_prices_product_id ON prices (product_id);

CREATE INDEX idx_prices_currency_code ON prices (currency_code);

CREATE INDEX idx_exchange_rates_currency_code ON exchange_rates (currency_code);

CREATE INDEX idx_titles_lang_code ON product_titles(lang_code);

CREATE INDEX idx_titles_product_id ON product_titles(product_id);

CREATE INDEX idx_titles_lang_prod ON product_titles(lang_code, product_id);
