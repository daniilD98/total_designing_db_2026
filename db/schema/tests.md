# Протокол проверок (tests.md)

Проверки выполнены автоматическим скриптом `run_all_checks.sql` под учётной записью `inspector` на базе, восстановленной из `foodexpress_dolgopolov.backup`. SQL каждой проверки приведён ниже: любую из них можно повторить вручную в DBeaver.

## Окружение

| Параметр | Значение |
|---|---|
| PostgreSQL version | `PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)` |
| Дата проверки | 2026-11-11 |
| Схема | `dolgopolov_food` |
| Роль-аудитор | `inspector` |

Порядок подготовки: пустая БД → `CREATE SCHEMA exts; CREATE EXTENSION "uuid-ossp" SCHEMA exts;` → `pg_restore --exit-on-error foodexpress_dolgopolov.backup` → `grants.sql` → вход под `inspector`. Бэкап сделан командой `pg_dump -Fc -n dolgopolov_food --no-owner --no-privileges --schema-only`, поэтому в нём нет данных, ролей и GRANT-ов; данные создаёт `insert_test_data`.

---

## Сводка

Всего автоматических проверок: **69**, успешно: **69**, провалено: **0**. Дополнительно: восстановление бэкапа (A.1) и план запроса (H.3, H.4).

---

## A. Подготовка

### A.1. Восстановление бэкапа

```bash
createdb foodexpress_check
psql -d foodexpress_check -c 'CREATE SCHEMA exts; CREATE EXTENSION "uuid-ossp" SCHEMA exts;'
pg_restore -d foodexpress_check --exit-on-error foodexpress_dolgopolov.backup
psql -d foodexpress_check -f grants.sql
```

Ожидается: без ошибок.

Факт: `pg_restore --exit-on-error` завершился с кодом 0, `grants.sql` — с кодом 0, сообщений об ошибках нет.

Вердикт: OK

### A.2. Работаем под inspector

```sql
SELECT current_user = 'inspector', current_user::text
```

Ожидается: inspector

Факт: inspector

Вердикт: OK

---

## B. FOOD-101: структура схемы

_Проверка B.7 выполняется после генерации данных (до этого таблица `client` пуста)._

### B.1. Схема существует

```sql
SELECT count(*) = 1, coalesce(string_agg(schema_name, ','), 'нет') FROM information_schema.schemata WHERE schema_name = 'dolgopolov_food'
```

Ожидается: dolgopolov_food

Факт: dolgopolov_food

Вердикт: OK

### B.2. Расширение uuid-ossp в схеме exts

```sql
SELECT count(*) = 1, coalesce(string_agg(extname || ' / ' || extnamespace::regnamespace::text, ','), 'нет') FROM pg_extension WHERE extname = 'uuid-ossp' AND extnamespace::regnamespace::text = 'exts'
```

Ожидается: uuid-ossp, схема exts

Факт: uuid-ossp / exts

Вердикт: OK

### B.3. Таблицы: 12

```sql
SELECT count(*) = 12, count(*)::text FROM information_schema.tables WHERE table_schema = 'dolgopolov_food' AND table_type = 'BASE TABLE'
```

Ожидается: 12

Факт: 12

Вердикт: OK

### B.4. Все *_id — uuid (нарушений нет)

```sql
SELECT count(*) = 0, count(*)::text || ' нарушений' FROM information_schema.columns WHERE table_schema = 'dolgopolov_food' AND column_name LIKE '%_id' AND data_type <> 'uuid'
```

Ожидается: 0 нарушений

Факт: 0 нарушений

Вердикт: OK

### B.5. Enum-типы: 8

```sql
SELECT count(*) = 8, count(*)::text FROM (SELECT t.typname FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'dolgopolov_food' GROUP BY t.typname) x
```

Ожидается: 8

Факт: 8

Вердикт: OK

### B.6. FK-ограничения: не менее 15

```sql
SELECT count(*) >= 15, count(*)::text FROM pg_constraint WHERE contype = 'f' AND connamespace = 'dolgopolov_food'::regnamespace
```

Ожидается: >= 15

Факт: 18

Вердикт: OK

### B.7. Пароль — MD5 (длина 32)

```sql
SELECT count(*) > 0 AND bool_and(length(password) = 32), count(*)::text || ' клиентов; длина 32 у всех: ' || coalesce(bool_and(length(password) = 32)::text, '-') FROM client
```

Ожидается: у всех клиентов длина 32

Факт: 10 клиентов; длина 32 у всех: true

Вердикт: OK

### B.8. Вычисляемые commission и total_amount — NOT NULL; order.description — nullable

```sql
SELECT string_agg(column_name || '=' || is_nullable, ', ' ORDER BY column_name) = 'commission=NO, description=YES, total_amount=NO',
                  string_agg(column_name || '=' || is_nullable, ', ' ORDER BY column_name)
           FROM information_schema.columns WHERE table_schema = 'dolgopolov_food' AND table_name = 'order' AND column_name IN ('commission','total_amount','description')
```

Ожидается: commission NO, total_amount NO, description YES

Факт: commission=NO, description=YES, total_amount=NO

Вердикт: OK

### B.9. Размерность: цена numeric(7,2), выплата numeric(8,2), сумма заказа numeric(8,2)

```sql
SELECT (SELECT numeric_precision || ',' || numeric_scale FROM information_schema.columns WHERE table_schema='dolgopolov_food' AND table_name='product' AND column_name='price') = '7,2'
                  AND (SELECT numeric_precision || ',' || numeric_scale FROM information_schema.columns WHERE table_schema='dolgopolov_food' AND table_name='courier_pay' AND column_name='amount') = '8,2'
                  AND (SELECT numeric_precision || ',' || numeric_scale FROM information_schema.columns WHERE table_schema='dolgopolov_food' AND table_name='order' AND column_name='order_amount') = '8,2',
                  'price 7,2; courier_pay.amount 8,2; order_amount 8,2'
```

Ожидается: precision/scale как заданы

Факт: price 7,2; courier_pay.amount 8,2; order_amount 8,2

Вердикт: OK

### B.10. 1НФ: реквизиты и ФИО разложены на атомарные столбцы

```sql
SELECT (SELECT count(*) FROM information_schema.columns WHERE table_schema='dolgopolov_food' AND ((table_name='restaurant' AND column_name IN ('inn','ogrn','settlement_account')) OR (table_name='courier' AND column_name IN ('last_name','first_name','patronymic')))) = 6
                  AND (SELECT count(*) FROM information_schema.columns WHERE table_schema='dolgopolov_food' AND column_name IN ('company_details','fio')) = 0,
                  'атомарные столбцы на месте'
```

Ожидается: есть inn/ogrn/settlement_account и last_name/first_name/patronymic; company_details и fio нет

Факт: атомарные столбцы на месте

Вердикт: OK

---

## C. FOOD-102 / FOOD-103: `insert_test_data`, `erase_test_data`

### C.1. erase_test_data

```sql
CALL erase_test_data();
```

Ожидается: без ошибок

Факт: выполнено

Вердикт: OK

### C.2. insert_test_data(10)

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок

Факт: выполнено

Вердикт: OK

### C.3. Распределение строк (BR-11.7)

```sql
SELECT c1=10 AND c2=10 AND c3=10 AND c4=10 AND c5=50 AND c6=50 AND c7=50 AND c8=50 AND c9=50,
                  format('client=%s courier=%s category=%s restaurant=%s address=%s product=%s order=%s review=%s payment=%s', c1,c2,c3,c4,c5,c6,c7,c8,c9)
           FROM (SELECT (SELECT count(*) FROM client) c1, (SELECT count(*) FROM courier) c2, (SELECT count(*) FROM product_category) c3,
                        (SELECT count(*) FROM restaurant) c4, (SELECT count(*) FROM address) c5, (SELECT count(*) FROM product) c6,
                        (SELECT count(*) FROM "order") c7, (SELECT count(*) FROM review) c8, (SELECT count(*) FROM payment) c9) s
```

Ожидается: client, courier, product_category, restaurant = 10; address, product, order, review, payment = 50

Факт: client=10 courier=10 category=10 restaurant=10 address=50 product=50 order=50 review=50 payment=50

Вердикт: OK

### C.3a. courier_pay: 10 курьеров × 6 месяцев

```sql
SELECT count(*) = 60, count(*)::text FROM courier_pay
```

Ожидается: 60

Факт: 60

Вердикт: OK

### C.4. Адреса: 10 ресторанных из 50 (BR-11.7)

```sql
SELECT (SELECT count(*) FROM restaurant WHERE address_id IS NOT NULL) = 10 AND (SELECT count(*) FROM address) = 50,
                  'ресторанных ' || (SELECT count(*) FROM restaurant WHERE address_id IS NOT NULL) || ', всего ' || (SELECT count(*) FROM address)
```

Ожидается: ресторанных 10, всего 50

Факт: ресторанных 10, всего 50

Вердикт: OK

### C.5. Нет пустых строк (BR-11.3)

```sql
SELECT n = 0, n::text FROM (SELECT (SELECT count(*) FROM client WHERE login='' OR password='' OR phone_number='')
             + (SELECT count(*) FROM courier WHERE last_name='' OR first_name='' OR patronymic='' OR phone_number='')
             + (SELECT count(*) FROM address WHERE street='' OR house_number='' OR apartment_office='')
             + (SELECT count(*) FROM restaurant WHERE restaurant_name='' OR description='' OR inn='' OR ogrn='' OR settlement_account='')
             + (SELECT count(*) FROM product WHERE product_name='' OR description='' OR photo_url='')
             + (SELECT count(*) FROM product_category WHERE product_category_name='')
             + (SELECT count(*) FROM "order" WHERE description='')
             + (SELECT count(*) FROM review WHERE description='' OR photo_url='') AS n) s
```

Ожидается: 0

Факт: 0

Вердикт: OK

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
SELECT count(*) = 0, count(*)::text FROM "order" WHERE client_id IS NULL OR restaurant_id IS NULL OR courier_id IS NULL OR address_id IS NULL OR total_amount IS NULL
```

Ожидается: 0

Факт: 0

Вердикт: OK

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) >= 1, count(*)::text FROM courier WHERE status <> 'уволен'
```

Ожидается: >= 1

Факт: 8

Вердикт: OK

### C.8. courier_pay согласован с BR-10.2 (расхождений)

```sql
SELECT count(*) = 0, count(*)::text FROM courier_pay cp WHERE cp.amount <> round(coalesce((SELECT sum(o.commission) FROM "order" o WHERE o.courier_id = cp.courier_id AND o.status = 'доставлен' AND extract(year FROM o.order_timestamp) = cp.year AND extract(month FROM o.order_timestamp) = cp.month), 0) * cp.coefficient_used, 2)
```

Ожидается: 0

Факт: 0

Вердикт: OK

### C.9. Повторные вызовы insert_test_data (3 подряд без очистки)

```sql
SELECT (SELECT count(*) FROM client) = 40 AND (SELECT count(*) FROM "order") = 200,
                      'client=' || (SELECT count(*) FROM client) || ' order=' || (SELECT count(*) FROM "order")
```

Ожидается: без ошибок; client = 40, order = 200

Факт: client=40 order=200

Вердикт: OK

### C.11. Строки генерируются случайно (не одно значение)

```sql
SELECT (SELECT count(DISTINCT street) FROM address) > 25 AND (SELECT count(DISTINCT last_name) FROM courier) >= 5
                  AND (SELECT count(DISTINCT description) FROM product) > 25 AND (SELECT count(DISTINCT product_name) FROM product) > 25,
                  format('улиц %s из 50, фамилий %s из 10, описаний блюд %s из 50, названий блюд %s из 50',
                         (SELECT count(DISTINCT street) FROM address), (SELECT count(DISTINCT last_name) FROM courier),
                         (SELECT count(DISTINCT description) FROM product), (SELECT count(DISTINCT product_name) FROM product))
```

Ожидается: много разных улиц, названий, фамилий курьеров и описаний

Факт: улиц 35 из 50, фамилий 8 из 10, описаний блюд 50 из 50, названий блюд 40 из 50

Вердикт: OK

### C.11a. Длина строк: от 1 символа до размера varchar(N)

```sql
SELECT mn >= 1 AND mx_street <= 100 AND mx_name <= 100 AND mx_ln <= 50,
                  format('min=%s street_max=%s product_name_max=%s last_name_max=%s', mn, mx_street, mx_name, mx_ln)
           FROM (SELECT least((SELECT min(length(street)) FROM address), (SELECT min(length(product_name)) FROM product), (SELECT min(length(last_name)) FROM courier)) AS mn,
                        (SELECT max(length(street)) FROM address) AS mx_street, (SELECT max(length(product_name)) FROM product) AS mx_name,
                        (SELECT max(length(last_name)) FROM courier) AS mx_ln) s
```

Ожидается: min длина >= 1; max длина <= N

Факт: min=2 street_max=96 product_name_max=87 last_name_max=50

Вердикт: OK

### C.12. Рестораны: часы работы генерируются, закрытие позже открытия

```sql
SELECT count(DISTINCT work_start) > 1 AND count(DISTINCT work_end) > 1 AND bool_and(work_end > work_start),
                  count(DISTINCT work_start) || ' разных открытий, ' || count(DISTINCT work_end) || ' разных закрытий' FROM restaurant
```

Ожидается: разные work_start / work_end

Факт: 10 разных открытий, 10 разных закрытий

Вердикт: OK

### C.13. ИНН: 10 цифр, разные у каждого ресторана, код региона настоящий

```sql
SELECT count(DISTINCT inn) = count(*) AND bool_and(inn ~ '^[0-9]{10}$') AND bool_and(substr(inn,1,2) = ANY (ARRAY['01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20','21','22','23','24','25','26','27','28','29','30','31','32','33','34','35','36','37','38','39','40','41','42','43','44','45','46','47','48','49','50','51','52','53','54','55','56','57','58','59','60','61','62','63','64','65','66','67','68','69','70','71','72','73','74','75','76','77','78','79','83','86','87','89','91','92'])),
                  count(DISTINCT inn) || ' разных из ' || count(*) || '; регионы: ' || string_agg(DISTINCT substr(inn,1,2), ',') FROM restaurant
```

Ожидается: inn разные; первые 2 цифры — код региона РФ

Факт: 10 разных из 10; регионы: 05,09,19,58,60,64,67,68,89

Вердикт: OK

### C.13a. ОГРН: 13 цифр, контрольная цифра верна; р/с: 20 цифр

```sql
SELECT bool_and(ogrn ~ '^[0-9]{13}$' AND (substr(ogrn,1,12)::bigint % 11) % 10 = substr(ogrn,13,1)::int AND settlement_account ~ '^[0-9]{20}$'),
                  count(*) || ' ресторанов' FROM restaurant
```

Ожидается: все корректны

Факт: 10 ресторанов

Вердикт: OK

### C.14. Статусы генерируются (enum_range): заказы, оплаты, блюда, курьеры

```sql
SELECT (SELECT count(DISTINCT status) FROM "order") >= 3 AND (SELECT count(DISTINCT status) FROM payment) >= 2
                  AND (SELECT count(DISTINCT status) FROM product) >= 2 AND (SELECT count(DISTINCT payment_type) FROM payment) >= 2,
                  format('статусов заказа %s, оплаты %s, блюда %s, типов оплаты %s',
                         (SELECT count(DISTINCT status) FROM "order"), (SELECT count(DISTINCT status) FROM payment),
                         (SELECT count(DISTINCT status) FROM product), (SELECT count(DISTINCT payment_type) FROM payment))
```

Ожидается: несколько разных значений

Факт: статусов заказа 5, оплаты 3, блюда 3, типов оплаты 3

Вердикт: OK

### C.15. NULL только там, где разрешено: order.description, apartment_office, photo_url

```sql
SELECT (SELECT count(*) FROM "order" WHERE description IS NULL) BETWEEN 1 AND 49 AND (SELECT count(*) FROM address WHERE apartment_office IS NULL) BETWEEN 1 AND 49
                  AND (SELECT count(*) FROM product WHERE photo_url IS NULL) BETWEEN 1 AND 49,
                  format('order.description NULL: %s, apartment_office NULL: %s, product.photo_url NULL: %s',
                         (SELECT count(*) FROM "order" WHERE description IS NULL), (SELECT count(*) FROM address WHERE apartment_office IS NULL),
                         (SELECT count(*) FROM product WHERE photo_url IS NULL))
```

Ожидается: в этих полях есть и NULL, и значения

Факт: order.description NULL: 22, apartment_office NULL: 16, product.photo_url NULL: 15

Вердикт: OK

---

## D. Бизнес-правила на сгенерированных данных

### D.1. Нет «висячих» ссылок order_structure/payment/review → order

```sql
SELECT n = 0, n::text FROM (SELECT (SELECT count(*) FROM order_structure os LEFT JOIN "order" o USING (order_id) WHERE o.order_id IS NULL)
            + (SELECT count(*) FROM payment p LEFT JOIN "order" o USING (order_id) WHERE o.order_id IS NULL)
            + (SELECT count(*) FROM review r LEFT JOIN "order" o USING (order_id) WHERE o.order_id IS NULL) AS n) s
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.2. Минимальная сумма заказа 1000 (BR-1.8)

```sql
SELECT count(*) = 0, count(*)::text FROM "order" WHERE total_amount < 1000
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) = 0, count(*)::text FROM "order" WHERE round(order_amount * 0.10, 2) <> commission
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.4. total_amount = order_amount + commission

```sql
SELECT count(*) = 0, count(*)::text FROM "order" WHERE round(order_amount + commission, 2) <> total_amount
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.5. Доставка не раньше создания (BR-7.13)

```sql
SELECT count(*) = 0, count(*)::text FROM "order" WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) = 0, count(*)::text FROM "order" o LEFT JOIN client_address ca ON ca.client_id = o.client_id AND ca.address_id = o.address_id WHERE ca.client_id IS NULL
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.7. Все блюда заказа из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id) = 0, count(DISTINCT os.order_id)::text FROM order_structure os JOIN "order" o ON os.order_id = o.order_id JOIN product p ON os.product_id = p.product_id WHERE p.restaurant_id <> o.restaurant_id
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.8. Не более одной успешной оплаты на заказ (BR-8.1)

```sql
SELECT count(*) = 0, count(*)::text FROM (SELECT order_id FROM payment WHERE status = 'успех' GROUP BY order_id HAVING count(*) > 1) x
```

Ожидается: 0 заказов с > 1 успешной оплатой

Факт: 0

Вердикт: OK

### D.8a. Доставленный заказ оплачен успешно (генератор)

```sql
SELECT count(*) = 0, count(*)::text FROM "order" o WHERE o.status = 'доставлен' AND NOT EXISTS (SELECT 1 FROM payment p WHERE p.order_id = o.order_id AND p.status = 'успех')
```

Ожидается: 0 доставленных без успешной оплаты

Факт: 0

Вердикт: OK

### D.8b. order.pay_status согласован с попытками оплаты (BR-8.7)

```sql
SELECT count(*) = 0, count(*)::text FROM "order" o WHERE o.pay_status IS DISTINCT FROM (SELECT CASE WHEN bool_or(p.status = 'успех') THEN 'оплачен' WHEN bool_or(p.status = 'в_обработке') THEN 'ожидает' WHEN count(*) > 0 THEN 'ошибка' ELSE 'ожидает' END::order_pay_status FROM payment p WHERE p.order_id = o.order_id)
```

Ожидается: 0 расхождений

Факт: 0

Вердикт: OK

### D.9. Сумма оплаты = total_amount (BR-8.4)

```sql
SELECT count(*) = 0, count(*)::text FROM payment p JOIN "order" o ON p.order_id = o.order_id WHERE p.amount <> o.total_amount
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.10. Нет дубликатов client_address (BR-2.5)

```sql
SELECT count(*) = 0, count(*)::text FROM (SELECT 1 FROM client_address GROUP BY client_id, address_id HAVING count(*) > 1) x
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.11. Нет дубликатов order_structure (BR-7.16)

```sql
SELECT count(*) = 0, count(*)::text FROM (SELECT 1 FROM order_structure GROUP BY order_id, product_id HAVING count(*) > 1) x
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.12. work_end > work_start (BR-4.4)

```sql
SELECT count(*) = 0, count(*)::text FROM restaurant WHERE work_end <= work_start
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.13. dismissal_date >= hire_date (BR-6.3)

```sql
SELECT count(*) = 0, count(*)::text FROM courier WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.14. Рейтинги блюд и ресторанов = среднему по отзывам (BR-9.6, 9.7)

```sql
SELECT n = 0, n::text || ' расхождений' FROM (
              SELECT (SELECT count(*) FROM product p WHERE p.rating IS DISTINCT FROM (SELECT round(avg(r.rating), 2) FROM review r WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id))
                   + (SELECT count(*) FROM restaurant s WHERE s.rating IS DISTINCT FROM (SELECT round(avg(r.rating), 2) FROM review r WHERE r.entity_type = 'ресторан' AND r.entity_id = s.restaurant_id)) AS n) s
```

Ожидается: 0 расхождений

Факт: 0 расхождений

Вердикт: OK

### D.15. Блюдо в отзыве есть в заказе, ресторан в отзыве — ресторан заказа (BR-9.2)

```sql
SELECT n = 0, n::text FROM (
              SELECT (SELECT count(*) FROM review r WHERE r.entity_type = 'блюдо' AND NOT EXISTS (SELECT 1 FROM order_structure os WHERE os.order_id = r.order_id AND os.product_id = r.entity_id))
                   + (SELECT count(*) FROM review r JOIN "order" o ON o.order_id = r.order_id WHERE r.entity_type = 'ресторан' AND r.entity_id <> o.restaurant_id) AS n) s
```

Ожидается: 0

Факт: 0

Вердикт: OK

---

## E. FOOD-104 / 105 / 106 / 107

### E.1. add_product — успешный вызов

```sql
CALL add_product(<ресторан>, <категория>, 'Тестовое блюдо', 250, 4.5, 'доступно', 'Описание', 'https://...');
```

Ожидается: after = before + 1

Факт: before=50 after=51

Вердикт: OK

### E.2. add_product — несуществующий ресторан

```sql
CALL add_product('0000…', …);
```

Ожидается: ошибка с понятным сообщением

Факт: insert or update on table "product" violates foreign key constraint "fk_product_restaurant"

Вердикт: OK

### E.2a. add_product — отрицательная цена

```sql
CALL add_product(…, -5, …);
```

Ожидается: ошибка с именем chk_product_price (BR-5.3)

Факт: new row for relation "product" violates check constraint "chk_product_price"

Вердикт: OK

### E.3. rating_change: отзывы 3, 4, 5 → рейтинг блюда

```sql
INSERT INTO review … (рейтинги 3, 4, 5 на одно блюдо); SELECT rating FROM product …;
```

Ожидается: 4.00

Факт: 4.00

Вердикт: OK

### E.4. rating_change: удаление отзыва «3» → 4.50, удаление всех → NULL

```sql
DELETE FROM review WHERE … rating = 3; … DELETE FROM review WHERE entity_id = …;
```

Ожидается: 4.50, затем NULL

Факт: 4.50, затем NULL

Вердикт: OK

### E.5. get_statistic(): строка на каждый ресторан

```sql
SELECT (SELECT count(*) FROM get_statistic()) = (SELECT count(*) FROM restaurant),
                  (SELECT count(*) FROM get_statistic()) || ' строк из ' || (SELECT count(*) FROM restaurant) || ' ресторанов'
```

Ожидается: число строк = числу ресторанов

Факт: 10 строк из 10 ресторанов

Вердикт: OK

### E.5a. get_statistic(): названия колонок

```sql
SELECT r ILIKE '%restaurant_name%' AND r ILIKE '%best_product_name%' AND r ILIKE '%total_amount%' AND r ILIKE '%avg_amount%' AND r ILIKE '%best_user%', r
           FROM (SELECT pg_get_function_result('get_statistic()'::regprocedure) AS r) s
```

Ожидается: restaurant_name, best_product_name, total_amount, avg_amount, best_user

Факт: TABLE(restaurant_name character varying, best_product_name character varying, total_amount numeric, avg_amount numeric, best_user character varying)

Вердикт: OK

### E.5b. get_statistic(): total_amount и avg_amount совпадают с независимым расчётом

```sql
SELECT count(*) = 0, count(*)::text || ' расхождений' FROM get_statistic() g JOIN restaurant r ON r.restaurant_name = g.restaurant_name
           JOIN (SELECT restaurant_id, sum(total_amount) s, avg(total_amount) a FROM "order" WHERE status = 'доставлен' GROUP BY 1) t ON t.restaurant_id = r.restaurant_id
           WHERE g.total_amount <> t.s OR g.avg_amount <> t.a
```

Ожидается: 0 расхождений

Факт: 0 расхождений

Вердикт: OK

### E.5c. get_statistic(): best_product — блюдо с максимальной суммой quantity

```sql
SELECT count(*) = 0, count(*)::text || ' неверных' FROM get_statistic() g JOIN restaurant r ON r.restaurant_name = g.restaurant_name
           WHERE g.best_product_name IS NOT NULL AND (SELECT sum(os.quantity) FROM order_structure os JOIN "order" o USING (order_id) JOIN product p ON p.product_id = os.product_id
                  WHERE o.status = 'доставлен' AND o.restaurant_id = r.restaurant_id AND p.product_name = g.best_product_name)
              < (SELECT max(q) FROM (SELECT sum(os.quantity) q FROM order_structure os JOIN "order" o USING (order_id) WHERE o.status = 'доставлен' AND o.restaurant_id = r.restaurant_id GROUP BY os.product_id) m)
```

Ожидается: 0 неверных

Факт: 0 неверных

Вердикт: OK

### E.5d. get_statistic(): best_user — клиент с максимальным числом заказов

```sql
SELECT count(*) = 0, count(*)::text || ' неверных' FROM get_statistic() g JOIN restaurant r ON r.restaurant_name = g.restaurant_name JOIN client c ON c.login = g.best_user
           WHERE (SELECT count(*) FROM "order" o WHERE o.status = 'доставлен' AND o.restaurant_id = r.restaurant_id AND o.client_id = c.client_id)
              < (SELECT max(n) FROM (SELECT count(*) n FROM "order" o WHERE o.status = 'доставлен' AND o.restaurant_id = r.restaurant_id GROUP BY o.client_id) m)
```

Ожидается: 0 неверных

Факт: 0 неверных

Вердикт: OK

### E.6. courier_salary(): выполняется; у уволенных коэффициент не меняется (BR-10.6)

```sql
CALL courier_salary();
```

Ожидается: без ошибок; сумма коэффициентов уволенных не изменилась

Факт: до=0.10 после=0.10

Вердикт: OK

### E.7. courier_salary(): повторные вызовы не создают дубликатов

```sql
CALL courier_salary(); CALL courier_salary();
```

Ожидается: число записей за месяц не изменилось (= числу курьеров)

Факт: до=10 после=10 курьеров=10

Вердикт: OK

### E.7a. courier_pay за текущий месяц: amount = coefficient_used × Σ комиссий

```sql
SELECT count(*) = 0, count(*)::text || ' расхождений' FROM courier_pay cp WHERE cp.year = extract(year FROM current_date) AND cp.month = extract(month FROM current_date)
           AND cp.amount <> round(coalesce((SELECT sum(o.commission) FROM "order" o WHERE o.courier_id = cp.courier_id AND o.status = 'доставлен' AND date_trunc('month', o.order_timestamp) = date_trunc('month', localtimestamp)), 0) * cp.coefficient_used, 2)
```

Ожидается: 0 расхождений

Факт: 0 расхождений

Вердикт: OK

---

## F. FOOD-108: представление `how_much_money`

### F.1. how_much_money: колонки

```sql
SELECT count(*) = 8 AND bool_and(column_name IN ('year_month','sum_no_commission','sum_with_commission','commission','prev_commission','commission_diff','courier_pay','net_profit')),
                  string_agg(column_name, ', ' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'dolgopolov_food' AND table_name = 'how_much_money'
```

Ожидается: year_month, sum_no_commission, sum_with_commission, commission, prev_commission, commission_diff, courier_pay, net_profit

Факт: year_month, sum_no_commission, sum_with_commission, commission, prev_commission, commission_diff, courier_pay, net_profit

Вердикт: OK

### F.2. how_much_money: непрерывная серия месяцев

```sql
SELECT count(*) = (extract(year FROM age(to_date(max(year_month),'YYYY-MM'), to_date(min(year_month),'YYYY-MM'))) * 12
                           + extract(month FROM age(to_date(max(year_month),'YYYY-MM'), to_date(min(year_month),'YYYY-MM'))) + 1),
                  count(*) || ' месяцев: ' || min(year_month) || ' … ' || max(year_month) FROM how_much_money
```

Ожидается: число строк = числу месяцев между первым и последним

Факт: 6 месяцев: 2026-06 … 2026-11

Вердикт: OK

### F.4. how_much_money: формулы (нарушений)

```sql
SELECT count(*) = 0, count(*)::text FROM how_much_money WHERE commission <> sum_with_commission - sum_no_commission OR net_profit <> commission - courier_pay OR commission_diff IS DISTINCT FROM (commission - prev_commission)
```

Ожидается: 0

Факт: 0

Вердикт: OK

### F.3. how_much_money: месяц без заказов присутствует с нулями (BR-11.9)

```sql
UPDATE "order" SET status = 'отменён' … за месяц −3; SELECT … FROM how_much_money; (с откатом)
```

Ожидается: строка за месяц без доставленных заказов есть, суммы = 0

Факт: строк найдено: 1

Вердикт: OK

---

## G. FOOD-109: права `inspector`

### G.1. Права на схему: USAGE, CREATE; USAGE на exts

```sql
SELECT has_schema_privilege('inspector','dolgopolov_food','USAGE') AND has_schema_privilege('inspector','dolgopolov_food','CREATE') AND has_schema_privilege('inspector','exts','USAGE'),
                  has_schema_privilege('inspector','dolgopolov_food','USAGE') || ' / ' || has_schema_privilege('inspector','dolgopolov_food','CREATE') || ' / ' || has_schema_privilege('inspector','exts','USAGE')
```

Ожидается: true / true / true

Факт: true / true / true

Вердикт: OK

### G.2. Права на таблицы и представление (SELECT, INSERT, UPDATE, DELETE, TRUNCATE)

```sql
SELECT count(*) = 0, count(*)::text || ' объектов без полных прав' FROM pg_class c WHERE c.relnamespace = 'dolgopolov_food'::regnamespace AND c.relkind IN ('r','v')
           AND NOT (has_table_privilege('inspector', c.oid, 'SELECT') AND has_table_privilege('inspector', c.oid, 'INSERT') AND has_table_privilege('inspector', c.oid, 'UPDATE')
                AND has_table_privilege('inspector', c.oid, 'DELETE') AND has_table_privilege('inspector', c.oid, 'TRUNCATE'))
```

Ожидается: 0 объектов без полных прав

Факт: 0 объектов без полных прав

Вердикт: OK

### G.3. information_schema.tables читается

```sql
SELECT count(*) FILTER (WHERE table_type='BASE TABLE') = 12 AND count(*) FILTER (WHERE table_type='VIEW') = 1,
                  count(*) FILTER (WHERE table_type='BASE TABLE') || ' таблиц, ' || count(*) FILTER (WHERE table_type='VIEW') || ' представлений' FROM information_schema.tables WHERE table_schema = 'dolgopolov_food'
```

Ожидается: 12 таблиц + 1 представление

Факт: 12 таблиц, 1 представлений

Вердикт: OK

### G.4. pg_catalog.pg_tables читается

```sql
SELECT count(*) = 12, count(*)::text FROM pg_catalog.pg_tables WHERE schemaname = 'dolgopolov_food'
```

Ожидается: 12

Факт: 12

Вердикт: OK

### G.5. EXECUTE на все функции и процедуры схемы

```sql
SELECT count(*) = 0, count(*)::text || ' без права EXECUTE' FROM pg_proc WHERE pronamespace = 'dolgopolov_food'::regnamespace AND NOT has_function_privilege('inspector', oid, 'EXECUTE')
```

Ожидается: 0 без права

Факт: 0 без права EXECUTE

Вердикт: OK

---

## H. Оптимизация `get_statistic` (BR-11.8)

_Для осмысленного плана набор расширен: `insert_test_data(200)` → 1000 заказов._

### H.3. План тела `get_statistic()` — `EXPLAIN ANALYZE`

```sql
EXPLAIN (ANALYZE, COSTS OFF)
<тело get_statistic(): CTE d (MATERIALIZED) / totals / best_users / best_products + LEFT JOIN-ы>;
```

Ожидается: один проход по таблице `"order"`, без оконных функций и коррелированных подзапросов.

Факт: таблица `"order"` читается **1 раз** (CTE `d`), `WindowAgg` и `SubPlan` в плане отсутствуют.

```
                                                      QUERY PLAN                                                       
-----------------------------------------------------------------------------------------------------------------------
 Hash Left Join (actual time=6.457..6.652 rows=200 loops=1)
   Hash Cond: (r.restaurant_id = bu.restaurant_id)
   CTE d
     ->  Seq Scan on "order" o (actual time=0.009..0.344 rows=499 loops=1)
           Filter: (status = 'доставлен'::order_status)
           Rows Removed by Filter: 501
   CTE best_users
     ->  GroupAggregate (actual time=0.387..0.902 rows=182 loops=1)
           Group Key: d_1.restaurant_id
           ->  GroupAggregate (actual time=0.354..0.545 rows=493 loops=1)
                 Group Key: d_1.restaurant_id, c.client_id
                 ->  Sort (actual time=0.351..0.378 rows=499 loops=1)
                       Sort Key: d_1.restaurant_id, c.client_id
                       Sort Method: quicksort  Memory: 63kB
                       ->  Hash Join (actual time=0.130..0.215 rows=499 loops=1)
                             Hash Cond: (c.client_id = d_1.client_id)
                             ->  Seq Scan on client c (actual time=0.006..0.028 rows=200 loops=1)
                             ->  Hash (actual time=0.105..0.106 rows=499 loops=1)
                                   Buckets: 1024  Batches: 1  Memory Usage: 40kB
                                   ->  CTE Scan on d d_1 (actual time=0.001..0.042 rows=499 loops=1)
   CTE best_products
     ->  GroupAggregate (actual time=3.337..4.470 rows=182 loops=1)
           Group Key: d_2.restaurant_id
           ->  GroupAggregate (actual time=3.287..3.912 rows=771 loops=1)
                 Group Key: d_2.restaurant_id, p.product_id
                 ->  Sort (actual time=3.278..3.353 rows=1473 loops=1)
                       Sort Key: d_2.restaurant_id, p.product_id
                       Sort Method: quicksort  Memory: 243kB
                       ->  Nested Loop (actual time=0.139..2.677 rows=1473 loops=1)
                             ->  Hash Join (actual time=0.122..0.799 rows=1473 loops=1)
                                   Hash Cond: (os.order_id = d_2.order_id)
                                   ->  Seq Scan on order_structure os (actual time=0.006..0.260 rows=3011 loops=1)
                                   ->  Hash (actual time=0.105..0.106 rows=499 loops=1)
                                         Buckets: 1024  Batches: 1  Memory Usage: 40kB
                                         ->  CTE Scan on d d_2 (actual time=0.001..0.040 rows=499 loops=1)
                             ->  Index Scan using pk_product on product p (actual time=0.001..0.001 rows=1 loops=1473)
                                   Index Cond: (product_id = os.product_id)
   ->  Hash Left Join (actual time=5.475..5.633 rows=200 loops=1)
         Hash Cond: (r.restaurant_id = bp.restaurant_id)
         ->  Hash Left Join (actual time=0.859..0.984 rows=200 loops=1)
               Hash Cond: (r.restaurant_id = t.restaurant_id)
               ->  Seq Scan on restaurant r (actual time=0.007..0.089 rows=200 loops=1)
               ->  Hash (actual time=0.796..0.797 rows=182 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 20kB
                     ->  Subquery Scan on t (actual time=0.676..0.767 rows=182 loops=1)
                           ->  HashAggregate (actual time=0.675..0.750 rows=182 loops=1)
                                 Group Key: d.restaurant_id
                                 Batches: 1  Memory Usage: 168kB
... (план сокращён)
```

Вердикт: OK

### H.4. Время выполнения

Факт: `Execution Time` на 1000 заказах и 200 ресторанах — 6.877 ms.

Вердикт: OK

---

## I. Очистка и повторная генерация

### I.1. erase_test_data очищает все 12 таблиц; повторный вызов не падает

```sql
SELECT s = 0, 'всего строк: ' || s FROM (SELECT (SELECT count(*) FROM client)+(SELECT count(*) FROM courier)+(SELECT count(*) FROM product_category)+(SELECT count(*) FROM restaurant)
                 +(SELECT count(*) FROM address)+(SELECT count(*) FROM product)+(SELECT count(*) FROM "order")+(SELECT count(*) FROM review)+(SELECT count(*) FROM payment)
                 +(SELECT count(*) FROM order_structure)+(SELECT count(*) FROM client_address)+(SELECT count(*) FROM courier_pay) AS s) x
```

Ожидается: во всех таблицах 0 строк

Факт: всего строк: 0

Вердикт: OK

### I.3. После очистки insert_test_data снова работает

```sql
SELECT count(*) = 50, count(*)::text FROM "order"
```

Ожидается: 50 заказов

Факт: 50

Вердикт: OK
