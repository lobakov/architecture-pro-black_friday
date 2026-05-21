## Задание 10. Миграция в Cassandra

### 10.1

Наиболее критичными с точки зрения целостности для нас являются сущности Carts и Inventory, неконсистентность данных в корзине
может серьезно повлиять на намерение приобрести товар, а неактуальные остатки в момент распродажи могут принести проблемы по результатам торговли.

Наиболее очевидным кандидатом является коллекция Products, тк она обновляется нечасто, но при этом у нее высочайшая нагрузка на чтение.
Коллекция Orders же терпит eventual consistency с небольшой задержкой, особенно с учетом того, что большинство заказов в списке будут завершенными.

### 10.2

Не работал с кассандрой, а в уроке тема кластерных ключей и прочего раскрыта слабо, поэтому воспользовался помощью интернета.
Насколько я понимаю, нам для эффективного поиска в cassandra надо построить денормализованные таблицы, для того чтобы осуществлять
эффективную выборку по разным полям.

#### Коллекция Products

Ключ партицирования остается тем же - product_id.
Дополнительная таблица для поиска товаров по категориям.

```
-- Основная таблица товаров
CREATE TABLE products (
    product_id   TEXT,
    name         TEXT,
    price        DECIMAL,
    category_id  TEXT,
    attributes   MAP<TEXT,TEXT>,
    created_at   TIMESTAMP,
    updated_at   TIMESTAMP,
    PRIMARY KEY (product_id)
);

CREATE TABLE products_by_category (
    category_id   TEXT,
    product_id    TEXT,
    name          TEXT,
    price         DECIMAL,
    created_at    TIMESTAMP,
    PRIMARY KEY (category_id, product_id)
);
```

#### Коллекция Orders

Ключ партицирования остается тем же - user_id.
Дополнительная таблица для поиска по orderId.

```
CREATE TABLE orders_by_user (
    user_id       TEXT,
    order_id      TEXT,
    items         LIST<item>,
    status        TEXT,
    total         DECIMAL,
    currency      TEXT,
    shipping_address TEXT,
    created_at    TIMESTAMP,
    updated_at    TIMESTAMP,
    PRIMARY KEY (user_id, order_id)
);

CREATE TABLE orders_by_id (
    order_id      TEXT,
    user_id       TEXT,
    created_at    TIMESTAMP,
    items         LIST<FROZEN<order_item>>,
    status        TEXT,
    total         DECIMAL,
    currency      TEXT,
    shipping_address MAP<TEXT,TEXT>,
    updated_at    TIMESTAMP,
    PRIMARY KEY (order_id)
);
```

### 10.3

Cassandra поддерживает использоваине всех механизмов сразу, можно настроить и hinted-handoff и read-repair, одновременно,
вопрос в настройках

Для Orders можно настроить агрессивный read repair и максимальное окно для hinted handoff, для Products оба этих механизма
можно сделать менее агрессивными чтобы не влиять на чтение.
Anti-entropy repair для обеих коллекций можно сделать более частым инкрементальным (например каждый день) и редким полным (раз в неделю).
