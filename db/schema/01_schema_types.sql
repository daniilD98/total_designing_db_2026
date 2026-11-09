-- Создание схемы

CREATE SCHEMA IF NOT EXISTS dolgopolov_food;
SET search_path TO dolgopolov_food, exts, public;

-- Создание типов ENUM для таблиц

CREATE TYPE restaurant_status AS ENUM ('активен', 'неактивен');
CREATE TYPE courier_status AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');
CREATE TYPE product_status AS ENUM ('доступно', 'нет_в_наличии', 'архив'); 
CREATE TYPE order_status AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');
CREATE TYPE order_pay_status AS ENUM ('ожидает', 'оплачен', 'ошибка');
CREATE TYPE payment_status AS ENUM ('успех', 'ошибка', 'в_обработке');                       
CREATE TYPE payment_type AS ENUM ('карта', 'наличные', 'безнал');             
CREATE TYPE review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ'); 

   SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder)
   FROM pg_type t JOIN pg_enum e ON t.oid = e.enumtypid
   GROUP BY t.typname ORDER BY 1;