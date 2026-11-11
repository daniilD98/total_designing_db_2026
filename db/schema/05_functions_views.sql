-- Задание FOOD-106. Статистика по ресторанам

SET search_path TO dolgopolov_food, exts, public;

CREATE OR REPLACE FUNCTION dolgopolov_food.get_statistic()
RETURNS TABLE (
    restaurant_name   varchar,
    best_product_name varchar,
    total_amount      numeric,
    avg_amount        numeric,
    best_user         varchar
)
LANGUAGE sql VOLATILE
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
    WITH d AS MATERIALIZED (      
        SELECT o.order_id, o.restaurant_id, o.client_id, o.total_amount
        FROM "order" o
        WHERE o.status = 'доставлен'
    ),
    totals AS (  
        SELECT d.restaurant_id,
               sum(d.total_amount) AS total_amount,
               avg(d.total_amount) AS avg_amount
        FROM d
        GROUP BY d.restaurant_id
    ),
    best_users AS (              
        SELECT x.restaurant_id,
               (array_agg(x.login ORDER BY x.cnt DESC, random()))[1] AS best_user
        FROM (SELECT d.restaurant_id, c.login, count(*) AS cnt
              FROM d
              JOIN client c ON c.client_id = d.client_id
              GROUP BY d.restaurant_id, c.client_id, c.login) x
        GROUP BY x.restaurant_id
    ),
    best_products AS (           
        SELECT x.restaurant_id,
               (array_agg(x.product_name ORDER BY x.qty DESC, random()))[1] AS best_product_name
        FROM (SELECT d.restaurant_id, p.product_name, sum(os.quantity) AS qty
              FROM d
              JOIN order_structure os ON os.order_id   = d.order_id
              JOIN product         p  ON p.product_id  = os.product_id
              GROUP BY d.restaurant_id, p.product_id, p.product_name) x
        GROUP BY x.restaurant_id
    )
    SELECT r.restaurant_name,
           bp.best_product_name,
           coalesce(t.total_amount, 0),        
           t.avg_amount,                  
           bu.best_user
    FROM restaurant r
    LEFT JOIN totals        t  ON t.restaurant_id  = r.restaurant_id
    LEFT JOIN best_products bp ON bp.restaurant_id = r.restaurant_id
    LEFT JOIN best_users    bu ON bu.restaurant_id = r.restaurant_id;
$$;

CREATE OR REPLACE VIEW dolgopolov_food.how_much_money AS
WITH RECURSIVE bounds AS (
    SELECT date_trunc('month', min(o.order_timestamp)) AS first_m,
           date_trunc('month', max(o.order_timestamp)) AS last_m
    FROM "order" o
    WHERE o.status = 'доставлен'
), months (m) AS (
    SELECT b.first_m FROM bounds b WHERE b.first_m IS NOT NULL
    UNION ALL
    SELECT mo.m + interval '1 month'
    FROM months mo, bounds b
    WHERE mo.m < b.last_m
), orders_m AS (
    SELECT date_trunc('month', o.order_timestamp) AS m,
           sum(o.order_amount) AS s_no,
           sum(o.total_amount) AS s_with
    FROM "order" o
    WHERE o.status = 'доставлен'
    GROUP BY 1
), pay_m AS (
    SELECT make_date(cp.year, cp.month, 1)::timestamp AS m,
           sum(cp.amount) AS pay
    FROM courier_pay cp
    GROUP BY 1
), base AS (
    SELECT mo.m,
           coalesce(om.s_no,   0) AS s_no,
           coalesce(om.s_with, 0) AS s_with,
           coalesce(pm.pay,    0) AS pay
    FROM months mo
    LEFT JOIN orders_m om ON om.m = mo.m
    LEFT JOIN pay_m    pm ON pm.m = mo.m
), calc AS (
    SELECT b.m, b.s_no, b.s_with, b.pay,
           b.s_with - b.s_no AS commission,
           lag(b.s_with - b.s_no) OVER (ORDER BY b.m) AS prev_commission
    FROM base b
)
SELECT to_char(c.m, 'YYYY-MM')                      AS year_month,
       c.s_no::numeric                              AS sum_no_commission,
       c.s_with::numeric                            AS sum_with_commission,
       c.commission::numeric                        AS commission,
       c.prev_commission::numeric                   AS prev_commission,
       (c.commission - c.prev_commission)::numeric  AS commission_diff,
       c.pay::numeric                               AS courier_pay,
       (c.commission - c.pay)::numeric              AS net_profit
FROM calc c
ORDER BY c.m;
