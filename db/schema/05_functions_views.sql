-- Задание FOOD-106. Статистика по ресторанам

SET search_path TO dolgopolov_food, exts, public;

CREATE OR REPLACE FUNCTION get_statistic()
RETURNS TABLE (
    restaurant_name   varchar,
    best_product_name varchar,
    total_amount      numeric,
    avg_amount        numeric,
    best_user         varchar
)
LANGUAGE sql STABLE
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
    WITH d AS MATERIALIZED (
        SELECT o.order_id, o.restaurant_id, o.client_id, o.total_amount AS amt
          FROM "order" o
         WHERE o.status = 'доставлен'
    ), by_client AS (
        SELECT d.restaurant_id, d.client_id, count(*) AS cnt, sum(d.amt) AS sum_amt
          FROM d
         GROUP BY d.restaurant_id, d.client_id
    ), rest_tot AS (
        SELECT bc.restaurant_id,
               sum(bc.sum_amt)                       AS sum_amt,
               round(sum(bc.sum_amt) / sum(bc.cnt), 2) AS avg_amt
          FROM by_client bc
         GROUP BY bc.restaurant_id
    ), best_client AS (                            
        SELECT DISTINCT ON (bc.restaurant_id) bc.restaurant_id, bc.client_id
          FROM by_client bc
         ORDER BY bc.restaurant_id, bc.cnt DESC, random()
    ), by_product AS (
        SELECT d.restaurant_id, os.product_id, sum(os.quantity) AS qty
          FROM d
          JOIN order_structure os ON os.order_id = d.order_id
         GROUP BY d.restaurant_id, os.product_id
    ), best_product AS (
        SELECT DISTINCT ON (bp.restaurant_id) bp.restaurant_id, bp.product_id
          FROM by_product bp
         ORDER BY bp.restaurant_id, bp.qty DESC, random()
    )
    SELECT r.restaurant_name::varchar,
           p.product_name::varchar,
           coalesce(t.sum_amt, 0)::numeric,
           t.avg_amt::numeric,
           c.login::varchar               
      FROM restaurant r
      LEFT JOIN rest_tot     t  ON t.restaurant_id  = r.restaurant_id
      LEFT JOIN best_product bp ON bp.restaurant_id = r.restaurant_id
      LEFT JOIN product      p  ON p.product_id     = bp.product_id
      LEFT JOIN best_client  bc ON bc.restaurant_id = r.restaurant_id
      LEFT JOIN client       c  ON c.client_id      = bc.client_id
     ORDER BY r.restaurant_name;
$$;

-- Задание FOOD-108. Отчёт «сколько денег»

CREATE OR REPLACE VIEW how_much_money AS
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
    SELECT make_date(cp.year, cp.month, 1)::timestamp AS m, sum(cp.amount) AS pay
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
SELECT to_char(c.m, 'YYYY-MM')                    AS year_month,
       c.s_no::numeric                            AS sum_no_commission,
       c.s_with::numeric                          AS sum_with_commission,
       c.commission::numeric                      AS commission,
       c.prev_commission::numeric                 AS prev_commission,
       (c.commission - c.prev_commission)::numeric AS commission_diff,
       c.pay::numeric                             AS courier_pay,
       (c.commission - c.pay)::numeric            AS net_profit
  FROM calc c
 ORDER BY c.m;
