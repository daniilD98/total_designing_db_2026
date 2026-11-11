-- Задание FOOD-105. Триггер пересчёта рейтинга

SET search_path TO dolgopolov_food, exts, public;

CREATE OR REPLACE FUNCTION dolgopolov_food.rating_change() RETURNS trigger
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
DECLARE
    v_dishes uuid[] := ARRAY[]::uuid[];
    v_rests  uuid[] := ARRAY[]::uuid[];
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF NEW.entity_type = 'блюдо' THEN
            v_dishes := v_dishes || NEW.entity_id;
        ELSIF NEW.entity_type = 'ресторан' THEN
            v_rests := v_rests || NEW.entity_id;
        END IF;
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        IF OLD.entity_type = 'блюдо' THEN
            v_dishes := v_dishes || OLD.entity_id;
        ELSIF OLD.entity_type = 'ресторан' THEN
            v_rests := v_rests || OLD.entity_id;
        END IF;
    END IF;

    UPDATE product p
       SET rating = (SELECT avg(r.rating)
                       FROM review r
                      WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id)
     WHERE p.product_id = ANY (v_dishes);

    UPDATE restaurant s
       SET rating = (SELECT avg(r.rating)
                       FROM review r
                      WHERE r.entity_type = 'ресторан' AND r.entity_id = s.restaurant_id)
     WHERE s.restaurant_id = ANY (v_rests);

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
    IF TG_OP = 'UPDATE'
       AND (OLD.entity_type IS DISTINCT FROM NEW.entity_type
            OR OLD.entity_id IS DISTINCT FROM NEW.entity_id
            OR OLD.order_id  IS DISTINCT FROM NEW.order_id) THEN
        RAISE EXCEPTION
            'Нельзя менять объект или заказ отзыва: отзыв привязан к (order_id=%, entity_type=%, entity_id=%)',
            OLD.order_id, OLD.entity_type, OLD.entity_id;
    END IF;

    IF NEW.entity_type = 'блюдо' THEN
        IF NOT EXISTS (SELECT 1 FROM order_structure os
                        WHERE os.order_id = NEW.order_id AND os.product_id = NEW.entity_id) THEN
            RAISE EXCEPTION 'Отзыв на блюдо %: его нет в заказе % (BR-9.2)', NEW.entity_id, NEW.order_id;
        END IF;
    ELSIF NEW.entity_type = 'ресторан' THEN
        IF NOT EXISTS (SELECT 1 FROM "order" o
                        WHERE o.order_id = NEW.order_id AND o.restaurant_id = NEW.entity_id) THEN
            RAISE EXCEPTION 'Отзыв на ресторан %: заказ % оформлен не в нём (BR-9.2)', NEW.entity_id, NEW.order_id;
        END IF;
    ELSIF NEW.entity_id <> NEW.order_id THEN
        RAISE EXCEPTION  'Отзыв на заказ: entity_id (%) должен совпадать с order_id (%) (BR-9.2)',
    NEW.entity_id, NEW.order_id;
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
                     FROM "order" o
                     JOIN product p ON p.restaurant_id = o.restaurant_id
                    WHERE o.order_id = NEW.order_id AND p.product_id = NEW.product_id) THEN
        RAISE EXCEPTION 'Блюдо % не принадлежит ресторану заказа % (BR-7.3)', NEW.product_id, NEW.order_id;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_order_structure_check ON dolgopolov_food.order_structure;
CREATE TRIGGER trg_order_structure_check
    BEFORE INSERT OR UPDATE OF order_id, product_id ON dolgopolov_food.order_structure
    FOR EACH ROW EXECUTE FUNCTION dolgopolov_food.order_structure_check();

CREATE OR REPLACE FUNCTION dolgopolov_food.payment_sync_pay_status() RETURNS trigger
LANGUAGE plpgsql
SET search_path = dolgopolov_food, exts, pg_catalog
AS $$
DECLARE
    v_order uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_order := OLD.order_id;
    ELSE
        v_order := NEW.order_id;
    END IF;

    UPDATE "order" o
       SET pay_status = (SELECT CASE WHEN bool_or(p.status = 'успех')       THEN 'оплачен'
                                     WHEN bool_or(p.status = 'в_обработке') THEN 'ожидает'
                                     WHEN count(*) > 0                      THEN 'ошибка'
                                     ELSE 'ожидает'
                                END::order_pay_status
                           FROM payment p
                          WHERE p.order_id = o.order_id)
     WHERE o.order_id = v_order;

    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_payment_sync_pay_status ON dolgopolov_food.payment;
CREATE TRIGGER trg_payment_sync_pay_status
    AFTER INSERT OR UPDATE OF status OR DELETE ON dolgopolov_food.payment
    FOR EACH ROW EXECUTE FUNCTION dolgopolov_food.payment_sync_pay_status();