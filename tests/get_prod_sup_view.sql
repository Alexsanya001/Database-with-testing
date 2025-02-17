-- Example with view:
SELECT product_id, title, price
FROM get_products_by_supplier
WHERE supplier_id = 1
  AND lang_code = 'EN'
  AND currency_code = 'RON';
