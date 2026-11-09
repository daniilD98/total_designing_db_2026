-- Задание FOOD-105. Триггер пересчёта рейтинга

SET search_path TO dolgopolov_food, exts, public;

CREATE OR REPLACE FUNCTION dolgopolov_food.rating_change() RETURNS trigger
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
DECLARE
    v_types review_entity_type[] := ARRAY[]::review_entity_type[];
    v_ids   uuid[]               := ARRAY[]::uuid[];
    i       int;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_types := v_types || OLD.entity_type;
        v_ids   := v_ids   || OLD.entity_id;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_types := v_types || NEW.entity_type;
        v_ids   := v_ids   || NEW.entity_id;
    END IF;

    FOR i IN 1 .. coalesce(cardinality(v_ids), 0) LOOP
        IF v_types[i] = 'блюдо' THEN
            UPDATE dolgopolov_food.product p
               SET rating = (SELECT round(avg(r.rating), 2) FROM dolgopolov_food.review r
                              WHERE r.entity_type = 'блюдо' AND r.entity_id = v_ids[i])
             WHERE p.product_id = v_ids[i];
        ELSIF v_types[i] = 'ресторан' THEN
            UPDATE dolgopolov_food.restaurant s
               SET rating = (SELECT round(avg(r.rating), 2) FROM dolgopolov_food.review r
                              WHERE r.entity_type = 'ресторан' AND r.entity_id = v_ids[i])
             WHERE s.restaurant_id = v_ids[i];
        END IF;
    END LOOP;

    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_review_rating_change ON dolgopolov_food.review;
CREATE TRIGGER trg_review_rating_change
    AFTER INSERT OR UPDATE OR DELETE ON dolgopolov_food.review
    FOR EACH ROW EXECUTE FUNCTION dolgopolov_food.rating_change();


CREATE OR REPLACE FUNCTION dolgopolov_food.review_check() RETURNS trigger
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
BEGIN
    IF NEW.entity_type = 'блюдо' THEN
        IF NOT EXISTS (SELECT 1 FROM dolgopolov_food.order_structure os
                        WHERE os.order_id = NEW.order_id AND os.product_id = NEW.entity_id) THEN
            RAISE EXCEPTION 'Отзыв на блюдо %: его нет в заказе % (BR-9.2)', NEW.entity_id, NEW.order_id
                USING ERRCODE = 'foreign_key_violation';
        END IF;
        
    ELSIF NEW.entity_type = 'ресторан' THEN
        IF NOT EXISTS (SELECT 1 FROM dolgopolov_food."order" o
                        WHERE o.order_id = NEW.order_id AND o.restaurant_id = NEW.entity_id) THEN
            RAISE EXCEPTION 'Отзыв на ресторан %: заказ % оформлен не в нём (BR-9.2)', NEW.entity_id, NEW.order_id
                USING ERRCODE = 'foreign_key_violation';
        END IF;
        
    ELSE  -- 'заказ'
        IF NEW.entity_id <> NEW.order_id THEN
            RAISE EXCEPTION 'Отзыв на заказ: entity_id (%) должен совпадать с order_id (%) (BR-9.2)', NEW.entity_id, NEW.order_id
                USING ERRCODE = 'foreign_key_violation';
        END IF;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_review_check ON dolgopolov_food.review;
CREATE TRIGGER trg_review_check
    BEFORE INSERT OR UPDATE OF order_id, entity_type, entity_id ON dolgopolov_food.review
    FOR EACH ROW EXECUTE FUNCTION dolgopolov_food.review_check();

CREATE OR REPLACE FUNCTION dolgopolov_food.order_structure_check() RETURNS trigger
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1
                     FROM dolgopolov_food."order" o
                     JOIN dolgopolov_food.product p ON p.restaurant_id = o.restaurant_id
                    WHERE o.order_id = NEW.order_id AND p.product_id = NEW.product_id) THEN
        RAISE EXCEPTION 'Блюдо % не принадлежит ресторану заказа % (BR-7.3)', NEW.product_id, NEW.order_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_order_structure_check ON dolgopolov_food.order_structure;
CREATE TRIGGER trg_order_structure_check
    BEFORE INSERT OR UPDATE OF order_id, product_id ON dolgopolov_food.order_structure
    FOR EACH ROW EXECUTE FUNCTION dolgopolov_food.order_structure_check();

CREATE OR REPLACE FUNCTION dolgopolov_food.order_restaurant_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM dolgopolov_food.order_structure os 
               JOIN dolgopolov_food.product p ON p.product_id = os.product_id
                WHERE os.order_id = NEW.order_id AND p.restaurant_id <> NEW.restaurant_id) THEN
        RAISE EXCEPTION 'Нельзя сменить ресторан заказа %: в нём есть блюда другого ресторана (BR-7.3)', NEW.order_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_order_restaurant_guard ON dolgopolov_food."order";
CREATE TRIGGER trg_order_restaurant_guard
    BEFORE UPDATE OF restaurant_id ON dolgopolov_food."order"
    FOR EACH ROW WHEN (NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id)
    EXECUTE FUNCTION dolgopolov_food.order_restaurant_guard();

CREATE OR REPLACE FUNCTION dolgopolov_food.product_restaurant_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM dolgopolov_food.order_structure os 
               JOIN dolgopolov_food."order" o ON o.order_id = os.order_id
                WHERE os.product_id = NEW.product_id AND o.restaurant_id <> NEW.restaurant_id) THEN
        RAISE EXCEPTION 'Нельзя сменить ресторан блюда %: оно уже есть в заказах другого ресторана (BR-7.3)', NEW.product_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_product_restaurant_guard ON dolgopolov_food.product;
CREATE TRIGGER trg_product_restaurant_guard
    BEFORE UPDATE OF restaurant_id ON dolgopolov_food.product
    FOR EACH ROW WHEN (NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id)
    EXECUTE FUNCTION dolgopolov_food.product_restaurant_guard();

CREATE OR REPLACE FUNCTION dolgopolov_food.payment_sync_pay_status() RETURNS trigger
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
DECLARE
    v_order uuid;
    v_new   order_pay_status;
BEGIN
    FOREACH v_order IN ARRAY
        CASE TG_OP WHEN 'INSERT' THEN ARRAY[NEW.order_id]
                   WHEN 'DELETE' THEN ARRAY[OLD.order_id]
                   ELSE ARRAY(SELECT DISTINCT x FROM unnest(ARRAY[OLD.order_id, NEW.order_id]) x) END
    LOOP
        SELECT CASE
                   WHEN bool_or(p.status = 'успех')       THEN 'оплачен'
                   WHEN bool_or(p.status = 'в_обработке') THEN 'ожидает'
                   WHEN count(*) > 0                      THEN 'ошибка'   
                   ELSE 'ожидает'      
               END::order_pay_status
          INTO v_new
          FROM dolgopolov_food.payment p WHERE p.order_id = v_order;

        UPDATE dolgopolov_food."order" o SET pay_status = v_new
         WHERE o.order_id = v_order AND o.pay_status IS DISTINCT FROM v_new;
    END LOOP;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_payment_sync_pay_status ON dolgopolov_food.payment;
CREATE TRIGGER trg_payment_sync_pay_status
    AFTER INSERT OR UPDATE OF status, order_id OR DELETE ON dolgopolov_food.payment
    FOR EACH ROW EXECUTE FUNCTION dolgopolov_food.payment_sync_pay_status();