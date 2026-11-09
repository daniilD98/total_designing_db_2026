-- Задание FOOD-102. Генератор тестовых данных

CREATE OR REPLACE PROCEDURE dolgopolov_food.insert_test_data(value int)
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
DECLARE
    v_now timestamp := localtimestamp;
    v_win timestamp := date_trunc('month', localtimestamp - interval '5 months'); 
    
    v_cat uuid[]; 
    v_cour uuid[]; 
    v_clo timestamp[]; 
    v_chi timestamp[];
    v_addr uuid[]; 
    v_rest_addr uuid[]; 
    v_cli_addr uuid[];
    v_rest uuid[]; 
    v_cli uuid[];
    v_prod uuid[]; 
    v_price numeric[];

    i int; 
    j int; 
    n int; 
    ri int; 
    ki int; 
    idx int;
    
    v_c uuid; 
    v_a uuid; 
    v_oid uuid; 
    v_eid uuid;
    v_pids uuid[]; 
    v_qty numeric[];
    
    v_q numeric; 
    v_amount numeric; 
    v_total numeric;
    v_ts timestamp; 
    v_dts timestamp;
    v_st order_status; 
    v_rt review_entity_type;
    v_m timestamp;
    
    v_login text;
    v_phone text;
    v_new_id uuid;
    
    v_attempts int;
BEGIN
    IF value IS NULL OR value < 1 THEN
        RAISE EXCEPTION 'Параметр value должен быть >= 1';
    END IF;

    v_cat := ARRAY[]::uuid[];
    FOR i IN 1 .. value LOOP
        INSERT INTO product_category (product_category_name)
        VALUES ('Категория ' || substr(md5(random()::text), 1, 5))
        RETURNING product_category_id INTO v_new_id;
        v_cat := v_cat || v_new_id;
    END LOOP;

    v_cour := ARRAY[]::uuid[];
    v_clo := ARRAY[]::timestamp[];
    v_chi := ARRAY[]::timestamp[];
    FOR i IN 1 .. value LOOP
        DECLARE
            c_status courier_status;
            c_hire timestamp;
            c_dismiss timestamp;
            c_coeff numeric;
            c_enum_arr courier_status[];
        BEGIN
            c_enum_arr := enum_range(NULL::courier_status);
            c_hire := v_win + random() * interval '15 days';
            
            IF i = 1 THEN
                c_status := 'свободен'; 
            ELSIF random() < 0.2 THEN
                c_status := 'уволен';
            ELSE
                c_status := c_enum_arr[1 + floor(random() * cardinality(c_enum_arr))::int];
                IF c_status = 'уволен' THEN c_status := 'свободен'; END IF;
            END IF;
            
            IF c_status = 'уволен' THEN
                c_dismiss := c_hire + random() * (v_now - c_hire);
                c_coeff := 0.1;
            ELSE
                c_dismiss := NULL;
                c_coeff := 0.1;
            END IF;

            INSERT INTO courier (fio, phone_number, status, hire_date, dismissal_date, coefficient)
            VALUES ('Иванов Иван', '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0'), 
                    c_status, c_hire, c_dismiss, c_coeff)
            RETURNING courier_id INTO v_new_id;

            v_cour := v_cour || v_new_id;
            v_clo := v_clo || c_hire;
            IF c_dismiss IS NOT NULL THEN
                v_chi := v_chi || c_dismiss;
            ELSE
                v_chi := v_chi || v_now;
            END IF;
        END;
    END LOOP;

    v_addr := ARRAY[]::uuid[];
    FOR i IN 1 .. value * 5 LOOP
        INSERT INTO address (street, house_number, apartment_office)
        VALUES ('ул. Ленина', floor(random() * 100)::text, floor(random() * 50)::text)
        RETURNING address_id INTO v_new_id;
        v_addr := v_addr || v_new_id;
    END LOOP;
    v_rest_addr := v_addr[1:value];
    v_cli_addr := v_addr[value+1 : value*5];

    v_rest := ARRAY[]::uuid[];
    FOR i IN 1 .. value LOOP
        INSERT INTO restaurant (restaurant_name, address_id, description, work_start, work_end, company_details, rating, status)
        VALUES ('Ресторан ' || i, v_rest_addr[i], 'Описание', '09:00', '22:00', 'ИНН 1234567890', NULL, 
                (enum_range(NULL::restaurant_status))[1 + floor(random() * cardinality(enum_range(NULL::restaurant_status)))::int])
        RETURNING restaurant_id INTO v_new_id;
        v_rest := v_rest || v_new_id;
    END LOOP;

    v_cli := ARRAY[]::uuid[];
    FOR i IN 1 .. value LOOP
        v_attempts := 0;
        LOOP
            v_login := 'user_' || substr(replace(exts.uuid_generate_v4()::text, '-', ''), 1, 16);
            v_phone := '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0');
            
            BEGIN
                INSERT INTO client (login, password, phone_number)
                VALUES (v_login, md5(random()::text), v_phone)
                RETURNING client_id INTO v_new_id;
                EXIT;
            EXCEPTION WHEN unique_violation THEN
                v_attempts := v_attempts + 1;
                IF v_attempts > 5 THEN RAISE EXCEPTION 'Не удалось сгенерировать уникального клиента'; END IF;
            END;
        END LOOP;
        v_cli := v_cli || v_new_id;
    END LOOP;

    FOR i IN 1 .. value LOOP
        FOR j IN 1 .. 4 LOOP
            INSERT INTO client_address (client_id, address_id)
            VALUES (v_cli[i], v_cli_addr[(i-1)*4 + j])
            ON CONFLICT DO NOTHING;
        END LOOP;
    END LOOP;

    v_prod := ARRAY[]::uuid[];
    v_price := ARRAY[]::numeric[];
    FOR i IN 1 .. value * 5 LOOP
        DECLARE
            v_pr numeric := round((50 + random() * 1450)::numeric, 2);
            v_r_id uuid := v_rest[((i-1) / 5) + 1];
            v_c_id uuid := v_cat[(i % value) + 1];
        BEGIN
            INSERT INTO product (product_name, product_category_id, price, restaurant_id, photo_url, rating, status, description)
            VALUES ('Блюдо ' || i, v_c_id, v_pr, v_r_id, NULL, NULL, 
                    (enum_range(NULL::product_status))[1 + floor(random() * cardinality(enum_range(NULL::product_status)))::int],
                    'Вкусно')
            RETURNING product_id INTO v_new_id;
            
            v_prod := v_prod || v_new_id;
            v_price := v_price || v_pr;
        END;
    END LOOP;

    FOR i IN 1 .. value * 5 LOOP
        ri := floor(random() * value) + 1;
        v_c := v_cli[floor(random() * value) + 1];
        
        SELECT address_id INTO v_a FROM client_address WHERE client_id = v_c LIMIT 1;
        
        ki := floor(random() * value) + 1;
        v_ts := v_clo[ki] + random() * (v_chi[ki] - v_clo[ki]);
        
        n := floor(random() * 5) + 1;
        v_pids := ARRAY[]::uuid[];
        v_qty := ARRAY[]::numeric[];
        v_amount := 0;
        
        FOR j IN 1 .. n LOOP
            idx := (ri - 1) * 5 + j;
            v_q := 0.5 * (1 + floor(random() * 6)); -- 0.5 .. 3.0
            v_pids := v_pids || v_prod[idx];
            v_qty := v_qty || v_q;
            v_amount := v_amount + (v_q * v_price[idx]);
        END LOOP;

        IF v_amount < 1000 THEN
            idx := (ri - 1) * 5 + 1;
            WHILE v_amount < 1000 LOOP
                v_qty[1] := v_qty[1] + 0.5;
                v_amount := v_amount + (0.5 * v_price[idx]);
            END LOOP;
        END IF;

        v_st := (enum_range(NULL::order_status))[1 + floor(random() * cardinality(enum_range(NULL::order_status)))::int];
        
        IF v_st = 'доставлен' THEN
            v_dts := least(v_ts + interval '1 hour', v_now);
        ELSE
            v_dts := NULL;
        END IF;

        v_oid := exts.uuid_generate_v4();
        INSERT INTO "order" (order_id, courier_id, client_id, address_id, restaurant_id, order_timestamp, delivery_timestamp, order_amount, status, pay_status, description)
        VALUES (v_oid, v_cour[ki], v_c, v_a, v_rest[ri], v_ts, v_dts, v_amount, v_st, 'оплачен', 'Заказ')
        RETURNING total_amount INTO v_total;

        FOR j IN 1 .. n LOOP
            INSERT INTO order_structure (order_id, product_id, quantity)
            VALUES (v_oid, v_pids[j], v_qty[j]);
        END LOOP;

        INSERT INTO payment (order_id, payment_type, amount, transaction_id, payment_timestamp, status)
        VALUES (v_oid, 
                (enum_range(NULL::payment_type))[1 + floor(random() * cardinality(enum_range(NULL::payment_type)))::int], 
                v_total, exts.uuid_generate_v4(), least(v_ts + interval '10 minutes', v_now), 'успех');

        v_rt := (enum_range(NULL::review_entity_type))[1 + floor(random() * 3)::int];
        v_eid := CASE v_rt 
            WHEN 'блюдо' THEN v_pids[1 + floor(random() * n)::int]
            WHEN 'ресторан' THEN v_rest[ri]
            ELSE v_oid 
        END;
        
        INSERT INTO review (client_id, order_id, review_timestamp, entity_id, entity_type, description, photo_url, rating)
        VALUES (v_c, v_oid, 
                least(v_ts + interval '1 hour' + random() * interval '47 hours', v_now), 
                v_eid, v_rt, 'Отзыв', NULL, 1 + floor(random() * 5)::int);
    END LOOP;

    FOR i IN 0 .. 5 LOOP
        v_m := v_win + i * interval '1 month';

        INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
        SELECT extract(year from v_m), extract(month from v_m), c.courier_id, 
               coalesce(sum(o.commission), 0) * c.coefficient, 
               c.coefficient
        FROM courier c
        LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен' 
                           AND o.order_timestamp >= v_m AND o.order_timestamp < v_m + interval '1 month'
        WHERE c.courier_id = ANY(v_cour)
        GROUP BY c.courier_id, c.coefficient;

        UPDATE courier c
        SET coefficient = CASE 
            WHEN (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен' AND o.order_timestamp >= v_m AND o.order_timestamp < v_m + interval '1 month') > 500 THEN 0.5
            WHEN (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен' AND o.order_timestamp >= v_m AND o.order_timestamp < v_m + interval '1 month') > 250 THEN 0.3
            WHEN (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен' AND o.order_timestamp >= v_m AND o.order_timestamp < v_m + interval '1 month') > 150 THEN 0.2
            ELSE 0.1
        END
        WHERE c.courier_id = ANY(v_cour)
          AND (c.dismissal_date IS NULL OR date_trunc('month', c.dismissal_date::timestamp) > v_m); -- BR-10.6
    END LOOP;
END $$;

-- Задание FOOD-103. Удаление тестовых данных

CREATE OR REPLACE PROCEDURE dolgopolov_food.erase_test_data()
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
BEGIN
    TRUNCATE TABLE review, payment, order_structure, "order", courier_pay, courier,
                   product, product_category, restaurant, client_address, address, client;
END $$;

-- Задание FOOD-104. Добавление блюда

CREATE OR REPLACE PROCEDURE add_product(
    p_restaurant_id       uuid,
    p_product_category_id uuid,
    p_name                varchar,
    p_price               numeric,
    p_rating              numeric,
    p_status              product_status,
    p_description         text,
    p_photo_url           text DEFAULT NULL
)
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
DECLARE
    v_constraint text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM restaurant r WHERE r.restaurant_id = p_restaurant_id) THEN
        RAISE EXCEPTION 'Ресторан с restaurant_id = % не существует', p_restaurant_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM product_category c WHERE c.product_category_id = p_product_category_id) THEN
        RAISE EXCEPTION 'Категория с product_category_id = % не существует', p_product_category_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    BEGIN
        INSERT INTO product (product_name, product_category_id, price, restaurant_id,
                             photo_url, rating, status, description)
        VALUES (p_name, p_product_category_id, p_price, p_restaurant_id,
                p_photo_url, p_rating, p_status, p_description);
    EXCEPTION
        WHEN check_violation THEN
            GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
            RAISE EXCEPTION 'Блюдо не добавлено: нарушено ограничение % (цена=%, рейтинг=%)',
                v_constraint, p_price, p_rating USING ERRCODE = 'check_violation';
        WHEN not_null_violation THEN
            RAISE EXCEPTION 'Блюдо не добавлено: обязательное поле не заполнено (%)', SQLERRM
                USING ERRCODE = 'not_null_violation';
    END;
END $$;

--Задание FOOD-107. Зарплата курьеров

CREATE OR REPLACE PROCEDURE courier_salary()
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
               count(o.order_id)                         AS cnt,
               coalesce(sum(o.commission), 0)            AS comm,
               coalesce(cp.coefficient_used, c.coefficient) AS coef
          FROM courier c
          LEFT JOIN "order" o
                 ON o.courier_id = c.courier_id
                AND o.status = 'доставлен'
                AND o.order_timestamp >= v_start AND o.order_timestamp < v_end
          LEFT JOIN courier_pay cp
                 ON cp.courier_id = c.courier_id AND cp.year = v_y AND cp.month = v_m
         GROUP BY c.courier_id, c.status, cp.coefficient_used, c.coefficient
    ), upsert AS (
        INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
        SELECT v_y, v_m, s.courier_id, round(s.coef * s.comm, 2), s.coef
          FROM stat s
        ON CONFLICT (year, month, courier_id)
        DO UPDATE SET amount = EXCLUDED.amount, coefficient_used = EXCLUDED.coefficient_used
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