-- Задание FOOD-102. Генератор тестовых данных

SET search_path TO dolgopolov_food, exts, public;

CREATE OR REPLACE PROCEDURE dolgopolov_food.insert_test_data(value int)
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
DECLARE
    v_now     timestamp := localtimestamp;
    v_win     timestamp := date_trunc('month', localtimestamp - interval '5 months'); 
    v_alpha   text      := 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';
    v_regions text[]    := ARRAY['01','02','03','04','05','06','07','08','09','10','11','12','13','14','15',
                                 '16','17','18','19','20','21','22','23','24','25','26','27','28','29','30',
                                 '31','32','33','34','35','36','37','38','39','40','41','42','43','44','45',
                                 '46','47','48','49','50','51','52','53','54','55','56','57','58','59','60',
                                 '61','62','63','64','65','66','67','68','69','70','71','72','73','74','75',
                                 '76','77','78','79','83','86','87','89','91','92'];

    v_cat       uuid[];
    v_cour      uuid[];
    v_clo       timestamp[];   
    v_chi       timestamp[]; 
    v_addr      uuid[];
    v_rest_addr uuid[];
    v_cli_addr  uuid[];
    v_shuf      uuid[];
    v_rest      uuid[];
    v_cli       uuid[];
    v_prod      uuid[];
    v_price     numeric[];

    i int;  j int;  n int;  ri int;  ki int;  idx int;
    v_c uuid;  v_a uuid;  v_oid uuid;  v_eid uuid;
    v_ks int[];  v_pids uuid[];  v_qty numeric[];
    v_q numeric;  v_add numeric;  v_amount numeric;  v_total numeric;
    v_ts timestamp;  v_dts timestamp;
    v_st order_status;  v_pst payment_status;  v_pay order_pay_status;
    v_rt review_entity_type;
    v_m timestamp;
BEGIN
    IF value IS NULL OR value < 1 THEN
        RAISE EXCEPTION 'Параметр value должен быть >= 1, получено: %', value;
    END IF;

    WITH ins AS (
        INSERT INTO product_category (product_category_name)
        SELECT left(repeat(substring(v_alpha, 1, 1 + floor(random() * 33)::int),
                           1 + floor(random() * 3)::int), 100)
        FROM generate_series(1, value)
        RETURNING product_category_id
    )
    SELECT array_agg(product_category_id) INTO v_cat FROM ins;

    WITH base AS MATERIALIZED (
        SELECT g,
               v_win::date + floor(random() * 15)::int AS hire,
               CASE WHEN g = 1 THEN 'свободен'::courier_status
                    WHEN random() < 0.2 THEN 'уволен'::courier_status
                    ELSE (enum_range(NULL::courier_status))[
                             1 + floor(random() * cardinality(enum_range(NULL::courier_status)))::int]
               END AS st
        FROM generate_series(1, value) g
    ), ins AS (
        INSERT INTO courier (last_name, first_name, patronymic, phone_number,
                             status, hire_date, dismissal_date)
        SELECT left(repeat(substring(v_alpha, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 50),
               left(repeat(substring(v_alpha, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 50),
               CASE WHEN random() < 0.1 THEN NULL     -- отчества может не быть
                    ELSE left(repeat(substring(v_alpha, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 50)
               END,
               '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0'),
               b.st,
               b.hire,
               CASE WHEN b.st = 'уволен'
                    THEN b.hire + floor(random() * (current_date - b.hire + 1))::int
               END
        FROM base b
        RETURNING courier_id, hire_date, dismissal_date
    )
    SELECT array_agg(courier_id),
           array_agg(hire_date::timestamp),
           array_agg(least(coalesce(dismissal_date::timestamp + interval '23 hours 59 minutes', v_now),
                           v_now - interval '2 hours'))
    INTO v_cour, v_clo, v_chi
    FROM ins;

    WITH ins AS (
        INSERT INTO address (street, house_number, apartment_office)
        SELECT left(repeat(substring(v_alpha, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 100),
               (1 + floor(random() * 200))::int::text,
               CASE WHEN random() < 0.3 THEN NULL
                    ELSE (1 + floor(random() * 300))::int::text
               END
        FROM generate_series(1, value * 5)
        RETURNING address_id
    )
    SELECT array_agg(address_id) INTO v_addr FROM ins;
    v_rest_addr := v_addr[1 : value];
    v_cli_addr  := v_addr[value + 1 : value * 5];

    v_rest := ARRAY(SELECT exts.uuid_generate_v4() FROM generate_series(1, value));
    INSERT INTO restaurant (restaurant_id, restaurant_name, address_id, description,
                            work_start, work_end, inn, ogrn, settlement_account, status)
    SELECT r.id,
           left(repeat(substring(v_alpha, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 100),
           r.addr,
           substring(md5(random()::text) || md5(random()::text) || md5(random()::text),
                     1, 1 + floor(random() * 90)::int),
           r.work_start,
           r.work_start + r.duration,                   
           r.region || lpad(floor(random() * 100000000)::bigint::text, 8, '0'),
           r.ogrn12 || ((r.ogrn12::bigint % 11) % 10)::text,                            
           lpad(floor(random() * 10000000000)::bigint::text, 10, '0')
               || lpad(floor(random() * 10000000000)::bigint::text, 10, '0'),  
           (enum_range(NULL::restaurant_status))[
               1 + floor(random() * cardinality(enum_range(NULL::restaurant_status)))::int]
    FROM (SELECT g.*,
                 '1' || (10 + floor(random() * 16))::int::text || g.region
                     || lpad(floor(random() * 10000000)::bigint::text, 7, '0') AS ogrn12
          FROM (SELECT t.id, t.addr,
                       time '06:00' + floor(random() * 360)::int * interval '1 minute'  AS work_start,   
                       (360 + floor(random() * 300)::int) * interval '1 minute'         AS duration,
                       v_regions[1 + floor(random() * cardinality(v_regions))::int]     AS region
                FROM unnest(v_rest, v_rest_addr) AS t(id, addr)) g) r;

    v_cli := ARRAY[]::uuid[];
    WHILE cardinality(v_cli) < value LOOP
        WITH ins AS (
            INSERT INTO client (login, password, phone_number)
            SELECT 'user_' || substr(replace(exts.uuid_generate_v4()::text, '-', ''), 1, 16),
                   md5(random()::text),                                  -- BR-2.3
                   '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0')
            FROM generate_series(1, value - cardinality(v_cli))
            ON CONFLICT DO NOTHING
            RETURNING client_id
        )
        SELECT v_cli || coalesce(array_agg(client_id), ARRAY[]::uuid[]) INTO v_cli FROM ins;
    END LOOP;

    v_shuf := ARRAY(SELECT a FROM unnest(v_cli_addr) a ORDER BY random());
    INSERT INTO client_address (client_id, address_id)
    SELECT v_cli[((t.g - 1) % value)::int + 1], t.a
    FROM unnest(v_shuf) WITH ORDINALITY AS t(a, g);

    INSERT INTO client_address (client_id, address_id)
    SELECT v_cli[1 + floor(random() * value)::int],
           v_cli_addr[1 + floor(random() * (value * 4))::int]
    FROM generate_series(1, value)
    ON CONFLICT DO NOTHING;

    v_prod  := ARRAY(SELECT exts.uuid_generate_v4() FROM generate_series(1, value * 5));
    v_price := ARRAY(SELECT (50 + floor(random() * 1451))::numeric FROM generate_series(1, value * 5));
    INSERT INTO product (product_id, product_name, product_category_id, price, restaurant_id,
                         photo_url, status, description)
    SELECT t.p,
           left(repeat(substring(v_alpha, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 100),
           v_cat[1 + floor(random() * value)::int],
           t.pr,
           v_rest[((t.g - 1) / 5)::int + 1],
           CASE WHEN random() < 0.3 THEN NULL
                ELSE 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg'
           END,
           (enum_range(NULL::product_status))[
               1 + floor(random() * cardinality(enum_range(NULL::product_status)))::int],
           substring(md5(random()::text) || md5(random()::text) || md5(random()::text),
                     1, 1 + floor(random() * 90)::int)
    FROM unnest(v_prod, v_price) WITH ORDINALITY AS t(p, pr, g);

    FOR i IN 1 .. value * 5 LOOP
        ri := 1 + floor(random() * value)::int;            
        v_c := v_cli[1 + floor(random() * value)::int];  
        SELECT ca.address_id INTO v_a                          
        FROM client_address ca
        WHERE ca.client_id = v_c
        ORDER BY random()
        LIMIT 1;
        ki := 1 + floor(random() * value)::int;              
        v_ts := date_trunc('second', v_clo[ki] + (v_chi[ki] - v_clo[ki]) * random());  

        n := 1 + floor(random() * 5)::int;
        SELECT array_agg(k) INTO v_ks
        FROM (SELECT k FROM generate_series(1, 5) k ORDER BY random() LIMIT n) s;
        v_pids := ARRAY[]::uuid[];
        v_qty  := ARRAY[]::numeric[];
        v_amount := 0;
        FOR j IN 1 .. n LOOP
            idx := (ri - 1) * 5 + v_ks[j];
            v_q := 0.5 * (1 + floor(random() * 6)::int);    
            v_pids := v_pids || v_prod[idx];
            v_qty  := v_qty  || v_q;
            v_amount := v_amount + v_q * v_price[idx];
        END LOOP;
        IF v_amount < 1000 THEN   
            idx := (ri - 1) * 5 + v_ks[1];
            v_add := ceil((1000 - v_amount) / v_price[idx] * 2) / 2;
            v_qty[1] := v_qty[1] + v_add;
            v_amount := v_amount + v_add * v_price[idx];
        END IF;

        v_st := CASE WHEN random() < 0.4 THEN 'доставлен'::order_status
                     ELSE (enum_range(NULL::order_status))[
                              1 + floor(random() * cardinality(enum_range(NULL::order_status)))::int]
                END;
        v_dts := CASE WHEN v_st = 'доставлен' THEN v_ts + (20 + floor(random() * 71)::int) * interval '1 minute' END;

        v_pst := CASE WHEN v_st = 'доставлен' THEN 'успех'::payment_status
                      ELSE (enum_range(NULL::payment_status))[
                               1 + floor(random() * cardinality(enum_range(NULL::payment_status)))::int]
                 END;
        v_pay := CASE v_pst WHEN 'успех'       THEN 'оплачен'::order_pay_status
                            WHEN 'в_обработке' THEN 'ожидает'::order_pay_status
                            ELSE 'ошибка'::order_pay_status
                 END;

        v_oid := exts.uuid_generate_v4();
        INSERT INTO "order" (order_id, courier_id, client_id, address_id, restaurant_id,
                             order_timestamp, delivery_timestamp, order_amount, status, pay_status, description)
        VALUES (v_oid, v_cour[ki], v_c, v_a, v_rest[ri],
                v_ts, v_dts, v_amount, v_st, v_pay,
                CASE WHEN random() < 0.4 THEN NULL
                     ELSE substring(md5(random()::text) || md5(random()::text), 1, 1 + floor(random() * 60)::int)
                END)
        RETURNING total_amount INTO v_total;

        INSERT INTO order_structure (order_id, product_id, quantity)
        SELECT v_oid, t.p, t.q
        FROM unnest(v_pids, v_qty) AS t(p, q);

        INSERT INTO payment (order_id, payment_type, amount, transaction_id, payment_timestamp, status)
        VALUES (v_oid,
                (enum_range(NULL::payment_type))[
                    1 + floor(random() * cardinality(enum_range(NULL::payment_type)))::int],
                v_total,
                exts.uuid_generate_v4(),
                least(v_ts + random() * interval '10 minutes', v_now),
                v_pst);

        v_rt  := (enum_range(NULL::review_entity_type))[1 + floor(random() * 3)::int];
        v_eid := CASE v_rt WHEN 'блюдо'    THEN v_pids[1 + floor(random() * n)::int]
                           WHEN 'ресторан' THEN v_rest[ri]
                           ELSE v_oid
                 END;
        INSERT INTO review (client_id, order_id, review_timestamp, entity_id, entity_type,
                            description, photo_url, rating)
        VALUES (v_c, v_oid,
                least(v_ts + interval '1 hour' + random() * interval '47 hours', v_now),
                v_eid, v_rt,
                substring(md5(random()::text) || md5(random()::text), 1, 1 + floor(random() * 60)::int),
                CASE WHEN random() < 0.5 THEN NULL
                     ELSE 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg'
                END,
                1 + floor(random() * 5)::int);
    END LOOP;

    FOR i IN 0 .. 5 LOOP
        v_m := v_win + i * interval '1 month';

        WITH stat AS (
            SELECT c.courier_id,
                   c.status,
                   count(o.order_id) AS cnt,
                   coalesce(sum(o.commission), 0) AS comm,
                   coalesce(cp.coefficient_used, c.coefficient) AS coef
              FROM courier c
              LEFT JOIN "order" o
                     ON o.courier_id = c.courier_id
                    AND o.status = 'доставлен'
                    AND o.order_timestamp >= v_m 
                    AND o.order_timestamp < v_m + interval '1 month'
              LEFT JOIN courier_pay cp
                     ON cp.courier_id = c.courier_id 
                    AND cp.year = extract(year from v_m)::int 
                    AND cp.month = extract(month from v_m)::int
             WHERE c.courier_id = ANY(v_cour)
             GROUP BY c.courier_id, c.status, cp.coefficient_used, c.coefficient
        ), upsert AS (
            INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
            SELECT extract(year from v_m)::int, 
                   extract(month from v_m)::int, 
                   s.courier_id, 
                   round(s.coef * s.comm, 2), 
                   s.coef
              FROM stat s
            ON CONFLICT (year, month, courier_id)
            -- Обновляем ТОЛЬКО сумму, чтобы не перезаписать старый коэффициент
            DO UPDATE SET amount = EXCLUDED.amount
            RETURNING courier_id
        )
        UPDATE courier c
           SET coefficient = CASE WHEN s.cnt <= 150 THEN 0.1
                                  WHEN s.cnt <= 250 THEN 0.2
                                  WHEN s.cnt <= 500 THEN 0.3
                                  ELSE 0.5 END
          FROM stat s
         WHERE s.courier_id = c.courier_id
           AND s.status <> 'уволен';
    END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE dolgopolov_food.erase_test_data()
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
BEGIN
    TRUNCATE TABLE review, payment, order_structure, "order", courier_pay, courier,
                   product, product_category, restaurant, client_address, address, client;
END $$;

CREATE OR REPLACE PROCEDURE dolgopolov_food.add_product(
    p_restaurant_id       uuid,
    p_product_category_id uuid,
    p_name                varchar,
    p_price               numeric,
    p_rating              numeric,
    p_status              dolgopolov_food.product_status,
    p_description         text,
    p_photo_url           text DEFAULT NULL
)
LANGUAGE sql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
    INSERT INTO product (product_name, product_category_id, price, restaurant_id,
                         photo_url, rating, status, description)
    VALUES (p_name, p_product_category_id, p_price, p_restaurant_id,
            p_photo_url, p_rating, p_status, p_description);
$$;

CREATE OR REPLACE PROCEDURE dolgopolov_food.courier_salary()
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
DECLARE
    v_start timestamp := date_trunc('month', localtimestamp);
    v_end   timestamp := date_trunc('month', localtimestamp) + interval '1 month';
    v_y     int       := extract(year  FROM localtimestamp)::int;
    v_m     int       := extract(month FROM localtimestamp)::int;
BEGIN
    WITH stat AS (
        SELECT c.courier_id,
               c.status,
               count(o.order_id) AS cnt,
               coalesce(sum(o.commission), 0) AS comm,
               coalesce(cp.coefficient_used, c.coefficient) AS coef
          FROM courier c
          LEFT JOIN "order" o
                 ON o.courier_id = c.courier_id
                AND o.status = 'доставлен'
                AND o.order_timestamp >= v_start 
                AND o.order_timestamp < v_end
          LEFT JOIN courier_pay cp
                 ON cp.courier_id = c.courier_id 
                AND cp.year = v_y 
                AND cp.month = v_m
         GROUP BY c.courier_id, c.status, cp.coefficient_used, c.coefficient
    ), upsert AS (
        INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
        SELECT v_y, v_m, s.courier_id, round(s.coef * s.comm, 2), s.coef
          FROM stat s
        ON CONFLICT (year, month, courier_id)
        DO UPDATE SET amount = EXCLUDED.amount
        RETURNING courier_id
    )
    UPDATE courier c
       SET coefficient = CASE WHEN s.cnt <= 150 THEN 0.1
                              WHEN s.cnt <= 250 THEN 0.2
                              WHEN s.cnt <= 500 THEN 0.3
                              ELSE 0.5 END
      FROM stat s
     WHERE s.courier_id = c.courier_id
       AND s.status <> 'уволен';
END $$;
