#!/usr/bin/env python3
"""Generate e-commerce test data for PostgreSQL and MongoDB (1GB~10GB)."""

import argparse
import sys
import time


def parse_args():
    parser = argparse.ArgumentParser(description="Generate test data")
    parser.add_argument("--size", type=int, default=1, help="Data size in GB (1-10)")
    parser.add_argument("--pg-host", required=True, help="PostgreSQL host")
    parser.add_argument("--pg-port", type=int, default=5432)
    parser.add_argument("--pg-user", default="debezium")
    parser.add_argument("--pg-password", default="debezium123")
    parser.add_argument("--pg-db", default="ecommerce")
    parser.add_argument("--mongo-host", required=True, help="MongoDB host")
    parser.add_argument("--mongo-port", type=int, default=27017)
    return parser.parse_args()


def create_pg_schema(conn):
    """Create PostgreSQL tables."""
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            username VARCHAR(100) NOT NULL,
            email VARCHAR(200) NOT NULL,
            full_name VARCHAR(200),
            address TEXT,
            phone VARCHAR(50),
            created_at TIMESTAMP DEFAULT NOW()
        );
        CREATE TABLE IF NOT EXISTS products (
            id SERIAL PRIMARY KEY,
            name VARCHAR(300) NOT NULL,
            description TEXT,
            price DECIMAL(10,2) NOT NULL,
            category VARCHAR(100),
            stock INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT NOW()
        );
        CREATE TABLE IF NOT EXISTS orders (
            id SERIAL PRIMARY KEY,
            user_id INTEGER REFERENCES users(id),
            total_amount DECIMAL(12,2),
            status VARCHAR(50) DEFAULT 'pending',
            shipping_address TEXT,
            created_at TIMESTAMP DEFAULT NOW()
        );
        CREATE TABLE IF NOT EXISTS order_items (
            id SERIAL PRIMARY KEY,
            order_id INTEGER REFERENCES orders(id),
            product_id INTEGER REFERENCES products(id),
            quantity INTEGER NOT NULL,
            unit_price DECIMAL(10,2) NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reviews (
            id SERIAL PRIMARY KEY,
            user_id INTEGER REFERENCES users(id),
            product_id INTEGER REFERENCES products(id),
            rating INTEGER CHECK (rating BETWEEN 1 AND 5),
            comment TEXT,
            created_at TIMESTAMP DEFAULT NOW()
        );
    """)
    conn.commit()


def generate_pg_data(conn, fake, size_gb):
    """Generate PostgreSQL data in batches."""
    cur = conn.cursor()
    batch_size = 1000
    # Scale: ~100K rows per GB for mixed tables
    base_users = 50000 * size_gb
    base_products = 10000 * size_gb
    base_orders = 100000 * size_gb
    base_reviews = 80000 * size_gb

    print(f"Generating {base_users} users...")
    for i in range(0, base_users, batch_size):
        values = [(fake.user_name(), fake.email(), fake.name(), fake.address(), fake.phone_number())
                  for _ in range(min(batch_size, base_users - i))]
        args = ",".join(cur.mogrify("(%s,%s,%s,%s,%s)", v).decode() for v in values)
        cur.execute(f"INSERT INTO users (username, email, full_name, address, phone) VALUES {args}")
        if (i + batch_size) % 10000 == 0:
            conn.commit()
            print(f"  Users: {i + batch_size}/{base_users}")
    conn.commit()

    print(f"Generating {base_products} products...")
    categories = ["Electronics", "Books", "Clothing", "Home", "Sports", "Food", "Toys", "Health"]
    for i in range(0, base_products, batch_size):
        values = [(fake.catch_phrase(), fake.text(200), round(fake.pyfloat(min_value=1, max_value=999), 2),
                   fake.random_element(categories), fake.random_int(0, 1000))
                  for _ in range(min(batch_size, base_products - i))]
        args = ",".join(cur.mogrify("(%s,%s,%s,%s,%s)", v).decode() for v in values)
        cur.execute(f"INSERT INTO products (name, description, price, category, stock) VALUES {args}")
        if (i + batch_size) % 10000 == 0:
            conn.commit()
    conn.commit()

    print(f"Generating {base_orders} orders with items...")
    statuses = ["pending", "processing", "shipped", "delivered", "cancelled"]
    for i in range(0, base_orders, batch_size):
        chunk = min(batch_size, base_orders - i)
        values = [(fake.random_int(1, base_users), round(fake.pyfloat(min_value=10, max_value=5000), 2),
                   fake.random_element(statuses), fake.address())
                  for _ in range(chunk)]
        args = ",".join(cur.mogrify("(%s,%s,%s,%s)", v).decode() for v in values)
        cur.execute(f"INSERT INTO orders (user_id, total_amount, status, shipping_address) VALUES {args} RETURNING id")
        order_ids = [r[0] for r in cur.fetchall()]
        # Generate 1-3 items per order
        items = []
        for oid in order_ids:
            num_items = fake.random_int(1, 3)
            for _ in range(num_items):
                items.append((oid, fake.random_int(1, base_products), fake.random_int(1, 5),
                             round(fake.pyfloat(min_value=1, max_value=999), 2)))
        if items:
            args = ",".join(cur.mogrify("(%s,%s,%s,%s)", v).decode() for v in items)
            cur.execute(f"INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES {args}")
        if (i + batch_size) % 10000 == 0:
            conn.commit()
            print(f"  Orders: {i + batch_size}/{base_orders}")
    conn.commit()

    print(f"Generating {base_reviews} reviews...")
    for i in range(0, base_reviews, batch_size):
        values = [(fake.random_int(1, base_users), fake.random_int(1, base_products),
                   fake.random_int(1, 5), fake.text(300))
                  for _ in range(min(batch_size, base_reviews - i))]
        args = ",".join(cur.mogrify("(%s,%s,%s,%s)", v).decode() for v in values)
        cur.execute(f"INSERT INTO reviews (user_id, product_id, rating, comment) VALUES {args}")
        if (i + batch_size) % 10000 == 0:
            conn.commit()
    conn.commit()
    print("PostgreSQL data generation complete.")


def generate_mongo_data(db, fake, size_gb):
    """Generate MongoDB data in batches."""
    from pymongo import InsertOne
    batch_size = 1000
    base_users = 50000 * size_gb
    base_products = 10000 * size_gb
    base_orders = 100000 * size_gb
    base_reviews = 80000 * size_gb
    base_sessions = 20000 * size_gb

    print(f"Generating MongoDB users ({base_users})...")
    for i in range(0, base_users, batch_size):
        docs = [{"username": fake.user_name(), "email": fake.email(), "full_name": fake.name(),
                 "address": {"street": fake.street_address(), "city": fake.city(), "country": fake.country()},
                 "phone": fake.phone_number(), "created_at": fake.date_time_this_decade()}
                for _ in range(min(batch_size, base_users - i))]
        db.users.insert_many(docs)
        if (i + batch_size) % 10000 == 0:
            print(f"  Users: {i + batch_size}/{base_users}")

    print(f"Generating MongoDB products ({base_products})...")
    categories = ["Electronics", "Books", "Clothing", "Home", "Sports", "Food", "Toys", "Health"]
    for i in range(0, base_products, batch_size):
        docs = [{"name": fake.catch_phrase(), "description": fake.text(200),
                 "price": round(fake.pyfloat(min_value=1, max_value=999), 2),
                 "category": fake.random_element(categories),
                 "tags": [fake.word() for _ in range(fake.random_int(1, 5))],
                 "stock": fake.random_int(0, 1000)}
                for _ in range(min(batch_size, base_products - i))]
        db.products.insert_many(docs)

    print(f"Generating MongoDB orders ({base_orders})...")
    for i in range(0, base_orders, batch_size):
        docs = [{"user_id": fake.random_int(1, base_users),
                 "items": [{"product_id": fake.random_int(1, base_products),
                           "quantity": fake.random_int(1, 5),
                           "price": round(fake.pyfloat(min_value=1, max_value=999), 2)}
                          for _ in range(fake.random_int(1, 3))],
                 "total": round(fake.pyfloat(min_value=10, max_value=5000), 2),
                 "status": fake.random_element(["pending", "processing", "shipped", "delivered"]),
                 "created_at": fake.date_time_this_year()}
                for _ in range(min(batch_size, base_orders - i))]
        db.orders.insert_many(docs)
        if (i + batch_size) % 10000 == 0:
            print(f"  Orders: {i + batch_size}/{base_orders}")

    print(f"Generating MongoDB reviews ({base_reviews})...")
    for i in range(0, base_reviews, batch_size):
        docs = [{"user_id": fake.random_int(1, base_users),
                 "product_id": fake.random_int(1, base_products),
                 "rating": fake.random_int(1, 5), "comment": fake.text(300),
                 "created_at": fake.date_time_this_year()}
                for _ in range(min(batch_size, base_reviews - i))]
        db.reviews.insert_many(docs)

    print(f"Generating MongoDB sessions ({base_sessions})...")
    for i in range(0, base_sessions, batch_size):
        docs = [{"user_id": fake.random_int(1, base_users),
                 "session_token": fake.uuid4(), "ip_address": fake.ipv4(),
                 "user_agent": fake.user_agent(), "started_at": fake.date_time_this_month(),
                 "pages_viewed": [fake.uri_path() for _ in range(fake.random_int(1, 20))]}
                for _ in range(min(batch_size, base_sessions - i))]
        db.sessions.insert_many(docs)
    print("MongoDB data generation complete.")


def main():
    args = parse_args()
    if args.size < 1 or args.size > 10:
        print("Error: --size must be between 1 and 10")
        sys.exit(1)

    from faker import Faker
    fake = Faker()

    print(f"=== Generating ~{args.size}GB of e-commerce test data ===")
    start = time.time()

    # PostgreSQL
    import psycopg2
    print(f"\nConnecting to PostgreSQL at {args.pg_host}:{args.pg_port}...")
    pg_conn = psycopg2.connect(host=args.pg_host, port=args.pg_port, user=args.pg_user,
                                password=args.pg_password, dbname=args.pg_db)
    create_pg_schema(pg_conn)
    generate_pg_data(pg_conn, fake, args.size)
    pg_conn.close()

    # MongoDB
    import pymongo
    print(f"\nConnecting to MongoDB at {args.mongo_host}:{args.mongo_port}...")
    mongo_client = pymongo.MongoClient(f"mongodb://{args.mongo_host}:{args.mongo_port}/")
    mongo_db = mongo_client["ecommerce"]
    generate_mongo_data(mongo_db, fake, args.size)
    mongo_client.close()

    elapsed = time.time() - start
    print(f"\n=== Data generation complete in {elapsed:.1f}s ===")


if __name__ == "__main__":
    main()
