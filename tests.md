# Протокол проверок (tests.md)

Проверки выполнены автоматическим скриптом `run\_all\_checks.sql` под учётной записью `inspector` на базе, восстановленной из `foodexpress\_dolgopolov.backup`. SQL каждой проверки приведён ниже: любую из них можно повторить вручную в DBeaver.

## Окружение

|Параметр|Значение|
|-|-|
|PostgreSQL version|`PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)`|
|Дата проверки|2026-11-09|
|Схема|`dolgopolov\_food`|
|Роль-аудитор|`inspector`|

Порядок подготовки: пустая БД → `CREATE SCHEMA exts; CREATE EXTENSION "uuid-ossp" SCHEMA exts;` → `pg\_restore --exit-on-error foodexpress\_dolgopolov.backup` → `grants.sql` → вход под `inspector`. Бэкап сделан командой `pg\_dump -Fc -n dolgopolov\_food --no-owner --no-privileges --schema-only`, поэтому в нём нет данных, ролей и GRANT-ов; данные создаёт `insert\_test\_data`.

\---

## Сводка

Всего автоматических проверок: **57**, успешно: **57**, провалено: **0**.

\---

## A. Подготовка

### A.1. Восстановление бэкапа

```bash
createdb foodexpress\_check
psql -d foodexpress\_check -c 'CREATE SCHEMA exts; CREATE EXTENSION "uuid-ossp" SCHEMA exts;'
pg\_restore -d foodexpress\_check --exit-on-error foodexpress\_dolgopolov.backup
psql -d foodexpress\_check -f grants.sql
```

Ожидается: без ошибок.

Факт: `pg\_restore --exit-on-error` завершился с кодом 0, `grants.sql` — с кодом 0, сообщений об ошибках нет.

Вердикт: OK

### A.2. Работаем под inspector

```sql
SELECT current\_user = 'inspector', current\_user::text
```

Ожидается: inspector

Факт: inspector

Вердикт: OK

\---

## B. FOOD-101: структура схемы

*Проверка B.7 выполняется после генерации данных (до этого таблица `client` пуста).*

### B.1. Схема существует

```sql
SELECT count(\*) = 1, coalesce(string\_agg(schema\_name, ','), 'нет') FROM information\_schema.schemata WHERE schema\_name = 'dolgopolov\_food'
```

Ожидается: dolgopolov\_food

Факт: dolgopolov\_food

Вердикт: OK

### B.2. Расширение uuid-ossp в схеме exts

```sql
SELECT count(\*) = 1, coalesce(string\_agg(extname || ' / ' || extnamespace::regnamespace::text, ','), 'нет') FROM pg\_extension WHERE extname = 'uuid-ossp' AND extnamespace::regnamespace::text = 'exts'
```

Ожидается: uuid-ossp, схема exts

Факт: uuid-ossp / exts

Вердикт: OK

### B.3. Таблицы: 12

```sql
SELECT count(\*) = 12, count(\*)::text FROM information\_schema.tables WHERE table\_schema = 'dolgopolov\_food' AND table\_type = 'BASE TABLE'
```

Ожидается: 12

Факт: 12

Вердикт: OK

### B.4. Все \*\_id — uuid (нарушений нет)

```sql
SELECT count(\*) = 0, count(\*)::text || ' нарушений' FROM information\_schema.columns WHERE table\_schema = 'dolgopolov\_food' AND column\_name LIKE '%\_id' AND data\_type <> 'uuid'
```

Ожидается: 0 нарушений

Факт: 0 нарушений

Вердикт: OK

### B.5. Enum-типы: 8

```sql
SELECT count(\*) = 8, count(\*)::text FROM (SELECT t.typname FROM pg\_type t JOIN pg\_enum e ON e.enumtypid = t.oid JOIN pg\_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'dolgopolov\_food' GROUP BY t.typname) x
```

Ожидается: 8

Факт: 8

Вердикт: OK

### B.6. FK-ограничения: не менее 15

```sql
SELECT count(\*) >= 15, count(\*)::text FROM pg\_constraint WHERE contype = 'f' AND connamespace = 'dolgopolov\_food'::regnamespace
```

Ожидается: >= 15

Факт: 18

Вердикт: OK

### B.7. Пароль — MD5 (длина 32)

```sql
SELECT count(\*) > 0 AND bool\_and(length(password) = 32), count(\*)::text || ' клиентов; длина 32 у всех: ' || coalesce(bool\_and(length(password) = 32)::text, '-') FROM client
```

Ожидается: у всех клиентов длина 32

Факт: 10 клиентов; длина 32 у всех: true

Вердикт: OK

\---

## C. FOOD-102 / FOOD-103: `insert\_test\_data`, `erase\_test\_data`

### C.1. erase\_test\_data

```sql
CALL erase\_test\_data();
```

Ожидается: без ошибок

Факт: выполнено

Вердикт: OK

### C.2. insert\_test\_data(10)

```sql
CALL insert\_test\_data(10);
```

Ожидается: без ошибок

Факт: выполнено

Вердикт: OK

### C.3. Распределение строк (BR-11.7)

```sql
SELECT c1=10 AND c2=10 AND c3=10 AND c4=10 AND c5=50 AND c6=50 AND c7=50 AND c8=50 AND c9=50,
                  format('client=%s courier=%s category=%s restaurant=%s address=%s product=%s order=%s review=%s payment=%s', c1,c2,c3,c4,c5,c6,c7,c8,c9)
           FROM (SELECT (SELECT count(\*) FROM client) c1, (SELECT count(\*) FROM courier) c2, (SELECT count(\*) FROM product\_category) c3,
                        (SELECT count(\*) FROM restaurant) c4, (SELECT count(\*) FROM address) c5, (SELECT count(\*) FROM product) c6,
                        (SELECT count(\*) FROM "order") c7, (SELECT count(\*) FROM review) c8, (SELECT count(\*) FROM payment) c9) s
```

Ожидается: client, courier, product\_category, restaurant = 10; address, product, order, review, payment = 50

Факт: client=10 courier=10 category=10 restaurant=10 address=50 product=50 order=50 review=50 payment=50

Вердикт: OK

### C.3a. courier\_pay: 10 курьеров × 6 месяцев

```sql
SELECT count(\*) = 60, count(\*)::text FROM courier\_pay
```

Ожидается: 60

Факт: 60

Вердикт: OK

### C.4. Адреса: 10 ресторанных из 50 (BR-11.7)

```sql
SELECT (SELECT count(\*) FROM restaurant WHERE address\_id IS NOT NULL) = 10 AND (SELECT count(\*) FROM address) = 50,
                  'ресторанных ' || (SELECT count(\*) FROM restaurant WHERE address\_id IS NOT NULL) || ', всего ' || (SELECT count(\*) FROM address)
```

Ожидается: ресторанных 10, всего 50

Факт: ресторанных 10, всего 50

Вердикт: OK

### C.5. Нет пустых строк (BR-11.3)

```sql
SELECT n = 0, n::text FROM (SELECT (SELECT count(\*) FROM client WHERE login='' OR password='' OR phone\_number='')
             + (SELECT count(\*) FROM courier WHERE fio='' OR phone\_number='')
             + (SELECT count(\*) FROM address WHERE street='' OR house\_number='' OR apartment\_office='')
             + (SELECT count(\*) FROM restaurant WHERE restaurant\_name='' OR description='' OR company\_details='')
             + (SELECT count(\*) FROM product WHERE product\_name='' OR description='' OR photo\_url='')
             + (SELECT count(\*) FROM product\_category WHERE product\_category\_name='')
             + (SELECT count(\*) FROM "order" WHERE description='')
             + (SELECT count(\*) FROM review WHERE description='' OR photo\_url='') AS n) s
```

Ожидается: 0

Факт: 0

Вердикт: OK

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
SELECT count(\*) = 0, count(\*)::text FROM "order" WHERE client\_id IS NULL OR restaurant\_id IS NULL OR courier\_id IS NULL OR address\_id IS NULL OR total\_amount IS NULL
```

Ожидается: 0

Факт: 0

Вердикт: OK

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(\*) >= 1, count(\*)::text FROM courier WHERE status <> 'уволен'
```

Ожидается: >= 1

Факт: 9

Вердикт: OK

### C.8. courier\_pay согласован с BR-10.2 (расхождений)

```sql
SELECT count(\*) = 0, count(\*)::text FROM courier\_pay cp WHERE cp.amount <> round(coalesce((SELECT sum(o.commission) FROM "order" o WHERE o.courier\_id = cp.courier\_id AND o.status = 'доставлен' AND extract(year FROM o.order\_timestamp) = cp.year AND extract(month FROM o.order\_timestamp) = cp.month), 0) \* cp.coefficient\_used, 2)
```

Ожидается: 0

Факт: 0

Вердикт: OK

### C.9. Повторные вызовы insert\_test\_data (3 подряд без очистки)

```sql
SELECT (SELECT count(\*) FROM client) = 40 AND (SELECT count(\*) FROM "order") = 200,
                      'client=' || (SELECT count(\*) FROM client) || ' order=' || (SELECT count(\*) FROM "order")
```

Ожидается: без ошибок; client = 40, order = 200

Факт: client=40 order=200

Вердикт: OK

\---

## D. Бизнес-правила на сгенерированных данных

### D.1. Нет «висячих» ссылок order\_structure/payment/review → order

```sql
SELECT n = 0, n::text FROM (SELECT (SELECT count(\*) FROM order\_structure os LEFT JOIN "order" o USING (order\_id) WHERE o.order\_id IS NULL)
            + (SELECT count(\*) FROM payment p LEFT JOIN "order" o USING (order\_id) WHERE o.order\_id IS NULL)
            + (SELECT count(\*) FROM review r LEFT JOIN "order" o USING (order\_id) WHERE o.order\_id IS NULL) AS n) s
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.2. Минимальная сумма заказа 1000 (BR-1.8)

```sql
SELECT count(\*) = 0, count(\*)::text FROM "order" WHERE total\_amount < 1000
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(\*) = 0, count(\*)::text FROM "order" WHERE round(order\_amount \* 0.10, 2) <> commission
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.4. total\_amount = order\_amount + commission

```sql
SELECT count(\*) = 0, count(\*)::text FROM "order" WHERE round(order\_amount + commission, 2) <> total\_amount
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.5. Доставка не раньше создания (BR-7.13)

```sql
SELECT count(\*) = 0, count(\*)::text FROM "order" WHERE delivery\_timestamp IS NOT NULL AND delivery\_timestamp < order\_timestamp
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(\*) = 0, count(\*)::text FROM "order" o LEFT JOIN client\_address ca ON ca.client\_id = o.client\_id AND ca.address\_id = o.address\_id WHERE ca.client\_id IS NULL
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.7. Все блюда заказа из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order\_id) = 0, count(DISTINCT os.order\_id)::text FROM order\_structure os JOIN "order" o ON os.order\_id = o.order\_id JOIN product p ON os.product\_id = p.product\_id WHERE p.restaurant\_id <> o.restaurant\_id
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT count(\*) = 0, count(\*)::text FROM (SELECT o.order\_id FROM "order" o LEFT JOIN payment p ON p.order\_id = o.order\_id AND p.status = 'успех' GROUP BY o.order\_id HAVING count(p.payment\_id) <> 1) x
```

Ожидается: 0 заказов с != 1 успешной оплатой

Факт: 0

Вердикт: OK

### D.9. Сумма оплаты = total\_amount (BR-8.4)

```sql
SELECT count(\*) = 0, count(\*)::text FROM payment p JOIN "order" o ON p.order\_id = o.order\_id WHERE p.amount <> o.total\_amount
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.10. Нет дубликатов client\_address (BR-2.5)

```sql
SELECT count(\*) = 0, count(\*)::text FROM (SELECT 1 FROM client\_address GROUP BY client\_id, address\_id HAVING count(\*) > 1) x
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.11. Нет дубликатов order\_structure (BR-7.16)

```sql
SELECT count(\*) = 0, count(\*)::text FROM (SELECT 1 FROM order\_structure GROUP BY order\_id, product\_id HAVING count(\*) > 1) x
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.12. work\_end > work\_start (BR-4.4)

```sql
SELECT count(\*) = 0, count(\*)::text FROM restaurant WHERE work\_end <= work\_start
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.13. dismissal\_date >= hire\_date (BR-6.3)

```sql
SELECT count(\*) = 0, count(\*)::text FROM courier WHERE dismissal\_date IS NOT NULL AND dismissal\_date < hire\_date
```

Ожидается: 0

Факт: 0

Вердикт: OK

### D.14. Рейтинги блюд и ресторанов = среднему по отзывам (BR-9.6, 9.7)

```sql
SELECT n = 0, n::text || ' расхождений' FROM (
              SELECT (SELECT count(\*) FROM product p WHERE p.rating IS DISTINCT FROM (SELECT round(avg(r.rating), 2) FROM review r WHERE r.entity\_type = 'блюдо' AND r.entity\_id = p.product\_id))
                   + (SELECT count(\*) FROM restaurant s WHERE s.rating IS DISTINCT FROM (SELECT round(avg(r.rating), 2) FROM review r WHERE r.entity\_type = 'ресторан' AND r.entity\_id = s.restaurant\_id)) AS n) s
```

Ожидается: 0 расхождений

Факт: 0 расхождений

Вердикт: OK

### D.15. Блюдо в отзыве есть в заказе, ресторан в отзыве — ресторан заказа (BR-9.2)

```sql
SELECT n = 0, n::text FROM (
              SELECT (SELECT count(\*) FROM review r WHERE r.entity\_type = 'блюдо' AND NOT EXISTS (SELECT 1 FROM order\_structure os WHERE os.order\_id = r.order\_id AND os.product\_id = r.entity\_id))
                   + (SELECT count(\*) FROM review r JOIN "order" o ON o.order\_id = r.order\_id WHERE r.entity\_type = 'ресторан' AND r.entity\_id <> o.restaurant\_id) AS n) s
```

Ожидается: 0

Факт: 0

Вердикт: OK

\---

## E. FOOD-104 / 105 / 106 / 107: `add\_product`, `rating\_change`, `get\_statistic`, `courier\_salary`

### E.1. add\_product — успешный вызов

```sql
CALL add\_product(<ресторан>, <категория>, 'Тестовое блюдо', 250, 4.5, 'доступно', 'Описание', 'https://...');
```

Ожидается: after = before + 1

Факт: before=50 after=51

Вердикт: OK

### E.2. add\_product — несуществующий ресторан

```sql
CALL add\_product('0000…', …);
```

Ожидается: ошибка с понятным сообщением

Факт: Ресторан с restaurant\_id = 00000000-0000-0000-0000-000000000000 не существует

Вердикт: OK

### E.2a. add\_product — отрицательная цена

```sql
CALL add\_product(…, -5, …);
```

Ожидается: ошибка (BR-5.3)

Факт: Блюдо не добавлено: нарушено ограничение product\_price\_check (цена=-5, рейтинг=3)

Вердикт: OK

### E.3. rating\_change: отзывы 3, 4, 5 → рейтинг блюда

```sql
INSERT INTO review … (рейтинги 3, 4, 5 на одно блюдо); SELECT rating FROM product …;
```

Ожидается: 4.00

Факт: 4.00

Вердикт: OK

### E.4. rating\_change: удаление отзыва «3» → 4.50, удаление всех → NULL

```sql
DELETE FROM review WHERE … rating = 3; … DELETE FROM review WHERE entity\_id = …;
```

Ожидается: 4.50, затем NULL

Факт: 4.50, затем NULL

Вердикт: OK

### E.5. get\_statistic(): строка на каждый ресторан

```sql
SELECT (SELECT count(\*) FROM get\_statistic()) = (SELECT count(\*) FROM restaurant),
                  (SELECT count(\*) FROM get\_statistic()) || ' строк из ' || (SELECT count(\*) FROM restaurant) || ' ресторанов'
```

Ожидается: число строк = числу ресторанов

Факт: 10 строк из 10 ресторанов

Вердикт: OK

### E.5a. get\_statistic(): названия колонок

```sql
SELECT r ILIKE '%restaurant\_name%' AND r ILIKE '%best\_product\_name%' AND r ILIKE '%total\_amount%' AND r ILIKE '%avg\_amount%' AND r ILIKE '%best\_user%', r
           FROM (SELECT pg\_get\_function\_result('get\_statistic()'::regprocedure) AS r) s
```

Ожидается: restaurant\_name, best\_product\_name, total\_amount, avg\_amount, best\_user

Факт: TABLE(restaurant\_name character varying, best\_product\_name character varying, total\_amount numeric, avg\_amount numeric, best\_user character varying)

Вердикт: OK

### E.5b. get\_statistic(): total\_amount и avg\_amount совпадают с независимым расчётом

```sql
SELECT count(\*) = 0, count(\*)::text || ' расхождений' FROM get\_statistic() g JOIN restaurant r ON r.restaurant\_name = g.restaurant\_name
           JOIN (SELECT restaurant\_id, sum(total\_amount) s, round(avg(total\_amount), 2) a FROM "order" WHERE status = 'доставлен' GROUP BY 1) t ON t.restaurant\_id = r.restaurant\_id
           WHERE g.total\_amount <> t.s OR g.avg\_amount <> t.a
```

Ожидается: 0 расхождений

Факт: 0 расхождений

Вердикт: OK

### E.5c. get\_statistic(): best\_product — блюдо с максимальной суммой quantity

```sql
SELECT count(\*) = 0, count(\*)::text || ' неверных' FROM get\_statistic() g JOIN restaurant r ON r.restaurant\_name = g.restaurant\_name
           WHERE g.best\_product\_name IS NOT NULL AND (SELECT sum(os.quantity) FROM order\_structure os JOIN "order" o USING (order\_id) JOIN product p ON p.product\_id = os.product\_id
                  WHERE o.status = 'доставлен' AND o.restaurant\_id = r.restaurant\_id AND p.product\_name = g.best\_product\_name)
              < (SELECT max(q) FROM (SELECT sum(os.quantity) q FROM order\_structure os JOIN "order" o USING (order\_id) WHERE o.status = 'доставлен' AND o.restaurant\_id = r.restaurant\_id GROUP BY os.product\_id) m)
```

Ожидается: 0 неверных

Факт: 0 неверных

Вердикт: OK

### E.5d. get\_statistic(): best\_user — клиент с максимальным числом заказов

```sql
SELECT count(\*) = 0, count(\*)::text || ' неверных' FROM get\_statistic() g JOIN restaurant r ON r.restaurant\_name = g.restaurant\_name JOIN client c ON c.login = g.best\_user
           WHERE (SELECT count(\*) FROM "order" o WHERE o.status = 'доставлен' AND o.restaurant\_id = r.restaurant\_id AND o.client\_id = c.client\_id)
              < (SELECT max(n) FROM (SELECT count(\*) n FROM "order" o WHERE o.status = 'доставлен' AND o.restaurant\_id = r.restaurant\_id GROUP BY o.client\_id) m)
```

Ожидается: 0 неверных

Факт: 0 неверных

Вердикт: OK

### E.6. courier\_salary(): выполняется; у уволенных коэффициент не меняется (BR-10.6)

```sql
CALL courier\_salary();
```

Ожидается: без ошибок; сумма коэффициентов уволенных не изменилась

Факт: до=0.20 после=0.20

Вердикт: OK

### E.7. courier\_salary(): повторные вызовы не создают дубликатов

```sql
CALL courier\_salary(); CALL courier\_salary();
```

Ожидается: число записей за месяц не изменилось (= числу курьеров)

Факт: до=10 после=10 курьеров=10

Вердикт: OK

### E.7a. courier\_pay за текущий месяц: amount = coefficient\_used × Σ комиссий

```sql
SELECT count(\*) = 0, count(\*)::text || ' расхождений' FROM courier\_pay cp WHERE cp.year = extract(year FROM current\_date) AND cp.month = extract(month FROM current\_date)
           AND cp.amount <> round(coalesce((SELECT sum(o.commission) FROM "order" o WHERE o.courier\_id = cp.courier\_id AND o.status = 'доставлен' AND date\_trunc('month', o.order\_timestamp) = date\_trunc('month', localtimestamp)), 0) \* cp.coefficient\_used, 2)
```

Ожидается: 0 расхождений

Факт: 0 расхождений

Вердикт: OK

\---

## F. FOOD-108: представление `how\_much\_money`

### F.1. how\_much\_money: колонки

```sql
SELECT count(\*) = 8 AND bool\_and(column\_name IN ('year\_month','sum\_no\_commission','sum\_with\_commission','commission','prev\_commission','commission\_diff','courier\_pay','net\_profit')),
                  string\_agg(column\_name, ', ' ORDER BY ordinal\_position) FROM information\_schema.columns WHERE table\_schema = 'dolgopolov\_food' AND table\_name = 'how\_much\_money'
```

Ожидается: year\_month, sum\_no\_commission, sum\_with\_commission, commission, prev\_commission, commission\_diff, courier\_pay, net\_profit

Факт: year\_month, sum\_no\_commission, sum\_with\_commission, commission, prev\_commission, commission\_diff, courier\_pay, net\_profit

Вердикт: OK

### F.2. how\_much\_money: непрерывная серия месяцев

```sql
SELECT count(\*) = (extract(year FROM age(to\_date(max(year\_month),'YYYY-MM'), to\_date(min(year\_month),'YYYY-MM'))) \* 12
                           + extract(month FROM age(to\_date(max(year\_month),'YYYY-MM'), to\_date(min(year\_month),'YYYY-MM'))) + 1),
                  count(\*) || ' месяцев: ' || min(year\_month) || ' … ' || max(year\_month) FROM how\_much\_money
```

Ожидается: число строк = числу месяцев между первым и последним

Факт: 5 месяцев: 2026-06 … 2026-10

Вердикт: OK

### F.4. how\_much\_money: формулы (нарушений)

```sql
SELECT count(\*) = 0, count(\*)::text FROM how\_much\_money WHERE commission <> sum\_with\_commission - sum\_no\_commission OR net\_profit <> commission - courier\_pay OR commission\_diff IS DISTINCT FROM (commission - prev\_commission)
```

Ожидается: 0

Факт: 0

Вердикт: OK

### F.3. how\_much\_money: месяц без заказов присутствует с нулями (BR-11.9)

```sql
UPDATE "order" SET status = 'отменён' … за месяц −3; SELECT … FROM how\_much\_money; (с откатом)
```

Ожидается: строка за месяц без доставленных заказов есть, суммы = 0

Факт: строк найдено: 1

Вердикт: OK

\---

## G. FOOD-109: права `inspector`

### G.1. Права на схему: USAGE, CREATE; USAGE на exts

```sql
SELECT has\_schema\_privilege('inspector','dolgopolov\_food','USAGE') AND has\_schema\_privilege('inspector','dolgopolov\_food','CREATE') AND has\_schema\_privilege('inspector','exts','USAGE'),
                  has\_schema\_privilege('inspector','dolgopolov\_food','USAGE') || ' / ' || has\_schema\_privilege('inspector','dolgopolov\_food','CREATE') || ' / ' || has\_schema\_privilege('inspector','exts','USAGE')
```

Ожидается: true / true / true

Факт: true / true / true

Вердикт: OK

### G.2. Права на таблицы и представление (SELECT, INSERT, UPDATE, DELETE, TRUNCATE)

```sql
SELECT count(\*) = 0, count(\*)::text || ' объектов без полных прав' FROM pg\_class c WHERE c.relnamespace = 'dolgopolov\_food'::regnamespace AND c.relkind IN ('r','v')
           AND NOT (has\_table\_privilege('inspector', c.oid, 'SELECT') AND has\_table\_privilege('inspector', c.oid, 'INSERT') AND has\_table\_privilege('inspector', c.oid, 'UPDATE')
                AND has\_table\_privilege('inspector', c.oid, 'DELETE') AND has\_table\_privilege('inspector', c.oid, 'TRUNCATE'))
```

Ожидается: 0 объектов без полных прав

Факт: 0 объектов без полных прав

Вердикт: OK

### G.3. information\_schema.tables читается

```sql
SELECT count(\*) FILTER (WHERE table\_type='BASE TABLE') = 12 AND count(\*) FILTER (WHERE table\_type='VIEW') = 1,
                  count(\*) FILTER (WHERE table\_type='BASE TABLE') || ' таблиц, ' || count(\*) FILTER (WHERE table\_type='VIEW') || ' представлений' FROM information\_schema.tables WHERE table\_schema = 'dolgopolov\_food'
```

Ожидается: 12 таблиц + 1 представление

Факт: 12 таблиц, 1 представлений

Вердикт: OK

### G.4. pg\_catalog.pg\_tables читается

```sql
SELECT count(\*) = 12, count(\*)::text FROM pg\_catalog.pg\_tables WHERE schemaname = 'dolgopolov\_food'
```

Ожидается: 12

Факт: 12

Вердикт: OK

### G.5. EXECUTE на все функции и процедуры схемы

```sql
SELECT count(\*) = 0, count(\*)::text || ' без права EXECUTE' FROM pg\_proc WHERE pronamespace = 'dolgopolov\_food'::regnamespace AND NOT has\_function\_privilege('inspector', oid, 'EXECUTE')
```

Ожидается: 0 без права

Факт: 0 без права EXECUTE

Вердикт: OK

\---

## H. Оптимизация `get\_statistic` (BR-11.8)

*Для осмысленного плана набор расширен: `insert\_test\_data(200)` → 1000 заказов.*

### H.3. План тела `get\_statistic()` — `EXPLAIN ANALYZE`

```sql
EXPLAIN (ANALYZE, COSTS OFF)
<тело get\_statistic(): CTE d (MATERIALIZED) / by\_client / rest\_tot / best\_client / by\_product / best\_product + LEFT JOIN-ы>;
```

Ожидается: один проход по таблице `"order"`, без оконных функций, без коррелированных подзапросов.

Факт: таблица `"order"` читается **1 раз** (CTE `d`), `WindowAgg` и `SubPlan` в плане отсутствуют.

```
                                                    QUERY PLAN                                                     
-------------------------------------------------------------------------------------------------------------------
 Sort (actual time=2.234..2.248 rows=200 loops=1)
   Sort Key: ((r.restaurant\_name)::character varying)
   Sort Method: quicksort  Memory: 45kB
   CTE d
     ->  Seq Scan on "order" o (actual time=0.006..0.136 rows=202 loops=1)
           Filter: (status = 'доставлен'::order\_status)
           Rows Removed by Filter: 798
   CTE by\_client
     ->  HashAggregate (actual time=0.265..0.298 rows=202 loops=1)
           Group Key: d.restaurant\_id, d.client\_id
           Batches: 1  Memory Usage: 168kB
           ->  CTE Scan on d (actual time=0.010..0.177 rows=202 loops=1)
   CTE best\_client
     ->  Unique (actual time=0.449..0.472 rows=129 loops=1)
           ->  Sort (actual time=0.448..0.456 rows=202 loops=1)
                 Sort Key: bc\_2.restaurant\_id, bc\_2.cnt DESC, (random())
                 Sort Method: quicksort  Memory: 39kB
                 ->  CTE Scan on by\_client bc\_2 (actual time=0.280..0.351 rows=202 loops=1)
   CTE best\_product
     ->  Unique (actual time=0.926..0.968 rows=129 loops=1)
           ->  Sort (actual time=0.926..0.942 rows=445 loops=1)
                 Sort Key: bp\_1.restaurant\_id, bp\_1.qty DESC, (random())
                 Sort Method: quicksort  Memory: 56kB
                 ->  Subquery Scan on bp\_1 (actual time=0.640..0.759 rows=445 loops=1)
                       ->  HashAggregate (actual time=0.639..0.703 rows=445 loops=1)
                             Group Key: d\_1.restaurant\_id, os.product\_id
                             Batches: 1  Memory Usage: 309kB
                             ->  Hash Join (actual time=0.045..0.425 rows=620 loops=1)
                                   Hash Cond: (os.order\_id = d\_1.order\_id)
                                   ->  Seq Scan on order\_structure os (actual time=0.004..0.183 rows=2964 loops=1)
                                   ->  Hash (actual time=0.033..0.033 rows=202 loops=1)
                                         Buckets: 1024  Batches: 1  Memory Usage: 21kB
                                         ->  CTE Scan on d d\_1 (actual time=0.000..0.012 rows=202 loops=1)
   ->  Hash Left Join (actual time=2.017..2.141 rows=200 loops=1)
         Hash Cond: (r.restaurant\_id = t.restaurant\_id)
         ->  Hash Left Join (actual time=1.855..1.956 rows=200 loops=1)
               Hash Cond: (r.restaurant\_id = bp.restaurant\_id)
               ->  Hash Left Join (actual time=0.596..0.675 rows=200 loops=1)
                     Hash Cond: (r.restaurant\_id = bc.restaurant\_id)
                     ->  Seq Scan on restaurant r (actual time=0.010..0.060 rows=200 loops=1)
                     ->  Hash (actual time=0.577..0.578 rows=129 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 17kB
                           ->  Hash Right Join (actual time=0.521..0.561 rows=129 loops=1)
                                 Hash Cond: (c.client\_id = bc.client\_id)
... (план сокращён)
```

Вердикт: OK

### H.4. Время выполнения

Факт: `Execution Time` запроса на 1000 заказах и 200 ресторанах — 2.449 ms.

Вердикт: OK

\---

## I. Очистка и повторная генерация

### I.1. erase\_test\_data очищает все 12 таблиц; повторный вызов не падает

```sql
SELECT s = 0, 'всего строк: ' || s FROM (SELECT (SELECT count(\*) FROM client)+(SELECT count(\*) FROM courier)+(SELECT count(\*) FROM product\_category)+(SELECT count(\*) FROM restaurant)
                 +(SELECT count(\*) FROM address)+(SELECT count(\*) FROM product)+(SELECT count(\*) FROM "order")+(SELECT count(\*) FROM review)+(SELECT count(\*) FROM payment)
                 +(SELECT count(\*) FROM order\_structure)+(SELECT count(\*) FROM client\_address)+(SELECT count(\*) FROM courier\_pay) AS s) x
```

Ожидается: во всех таблицах 0 строк

Факт: всего строк: 0

Вердикт: OK

### I.3. После очистки insert\_test\_data снова работает

```sql
SELECT count(\*) = 50, count(\*)::text FROM "order"
```

Ожидается: 50 заказов

Факт: 50

Вердикт: OK

