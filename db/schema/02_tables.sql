SET search_path TO dolgopolov_food, exts, public;

-- Создание таблицы client

CREATE TABLE client(
client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
login varchar(50) unique not null,
password varchar(32) not null,
phone_number char(12) UNIQUE not NULL
);

-- Создание таблицы address

CREATE TABLE address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(100) NOT NULL,
    house_number varchar(10) NOT NULL,
    apartment_office varchar(10)
);

-- Создание таблицы client_address

CREATE TABLE client_address(
client_id  uuid NOT NULL,
address_id uuid NOT null,
PRIMARY KEY (client_id, address_id),
FOREIGN KEY (client_id) REFERENCES client (client_id) ON DELETE cascade,
FOREIGN KEY (address_id) REFERENCES address (address_id) ON DELETE RESTRICT
);

-- Создание таблицы product_category
CREATE TABLE product_category(
    product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(100) NOT NULL
);

-- Создание таблицы courier

CREATE TABLE courier(
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    last_name varchar(50) NOT NULL,
    first_name varchar(50) NOT NULL,
    patronymic varchar(50),   
    phone_number char(12) NOT NULL,
    status courier_status NOT NULL,
    hire_date date NOT NULL,
    dismissal_date date,
    coefficient numeric(3,2) NOT NULL DEFAULT 0.1,
    CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL)
    );
 
-- Создание таблицы restaurant

CREATE TABLE restaurant(
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100) NOT NULL,
    address_id uuid NOT null UNIQUE,
    description text NOT NULL,
    work_start time NOT NULL,
    work_end time NOT NULL,
    inn char(10) NOT NULL,   
    ogrn char(13) NOT NULL,
    settlement_account char(20) NOT NULL,
    rating numeric(3,2),
    status restaurant_status NOT NULL,
    FOREIGN KEY (address_id) references address (address_id) ON DELETE RESTRICT,
    CHECK (rating BETWEEN 0 AND 5),
    CHECK (work_end > work_start)
);

-- Создание таблицы product

CREATE TABLE product(
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name varchar(100) NOT NULL,
    product_category_id uuid NOT NULL,
    price numeric(7,2) NOT NULL,
    restaurant_id uuid NOT NULL,
    photo_url text,
    rating numeric(3,2),
    status product_status NOT NULL,
    description text NOT NULL,
    FOREIGN KEY (product_category_id) REFERENCES product_category (product_category_id) ON DELETE RESTRICT,
 	FOREIGN KEY (restaurant_id) REFERENCES restaurant (restaurant_id) ON DELETE RESTRICT,
 	CHECK (price >= 0),
    CHECK (rating BETWEEN 0 AND 5)   
);

-- Создание таблицы courier_pay

CREATE TABLE courier_pay(
    year int NOT NULL,
    month int NOT NULL,
    courier_id uuid NOT NULL,
    amount numeric(8,2) NOT NULL,
    coefficient_used numeric(3,2) NOT NULL,
    PRIMARY KEY (year, month, courier_id),
    FOREIGN KEY (courier_id) REFERENCES courier (courier_id) ON DELETE RESTRICT,
    CHECK (amount >= 0)
);

-- Создание таблицы "order"

CREATE TABLE "order" (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id uuid NOT NULL,
    client_id uuid NOT NULL,
    address_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    order_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp,
    order_amount numeric(8,2) NOT NULL,
    commission numeric(12,2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED NOT NULL,
    total_amount numeric(12,2) GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED NOT NULL,
    status order_status NOT NULL DEFAULT 'создан',
    pay_status order_pay_status NOT NULL DEFAULT 'ожидает',
    description text,
    FOREIGN KEY (courier_id) REFERENCES courier (courier_id) ON DELETE RESTRICT,
    FOREIGN KEY (client_id) REFERENCES client (client_id) ON DELETE RESTRICT,
    FOREIGN KEY (address_id) REFERENCES address (address_id) ON DELETE RESTRICT,
    FOREIGN KEY (restaurant_id) REFERENCES restaurant (restaurant_id) ON DELETE RESTRICT,
    FOREIGN KEY (client_id, address_id) REFERENCES client_address (client_id, address_id) ON DELETE RESTRICT,
    UNIQUE (order_id, client_id),
    UNIQUE (order_id, total_amount),
    CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CHECK (status <> 'доставлен' OR delivery_timestamp IS NOT NULL)
    );

-- Создание таблицы order_structure

CREATE TABLE order_structure(
    order_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity numeric(5,2) NOT NULL,
    PRIMARY KEY (order_id, product_id),
    FOREIGN KEY (order_id) REFERENCES "order" (order_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES product (product_id) ON DELETE RESTRICT,
    CHECK (quantity > 0)
);

-- Создание таблицы payment

CREATE TABLE payment(
    payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL,
    payment_type payment_type NOT NULL,
    amount numeric(9,2) NOT NULL,
    transaction_id uuid unique NOT NULL,
    payment_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    status payment_status NOT NULL,
    FOREIGN KEY (order_id) REFERENCES "order" (order_id) ON DELETE RESTRICT,
    FOREIGN KEY (order_id, amount) REFERENCES "order" (order_id, total_amount) ON DELETE RESTRICT
);

-- BR-8.1: не более одной успешной попытки на заказ

CREATE UNIQUE INDEX uq_payment_one_success ON payment (order_id) WHERE status = 'успех';

-- Создание таблицы review

CREATE TABLE review(
    review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id uuid NOT NULL,
    order_id uuid NOT NULL,
    review_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    entity_id uuid NOT NULL,
    entity_type review_entity_type NOT NULL,
    description text,
    photo_url text,
    rating numeric(3,2) NOT NULL,
    FOREIGN KEY (client_id) REFERENCES client (client_id) ON DELETE RESTRICT,
    FOREIGN KEY (order_id) REFERENCES "order" (order_id) ON DELETE RESTRICT,
    FOREIGN KEY (order_id, client_id) REFERENCES "order" (order_id, client_id) ON DELETE RESTRICT,
    UNIQUE (order_id, entity_type, entity_id),
    CHECK (rating BETWEEN 1 AND 5)
);