#!/bin/bash
set -e
dnf update -y
dnf install -y postgresql16-server postgresql16
postgresql-setup --initdb
# Enable WAL logical replication
sed -i "s/#wal_level = replica/wal_level = logical/" /var/lib/pgsql/data/postgresql.conf
sed -i "s/#max_replication_slots = 10/max_replication_slots = 10/" /var/lib/pgsql/data/postgresql.conf
sed -i "s/#max_wal_senders = 10/max_wal_senders = 10/" /var/lib/pgsql/data/postgresql.conf
# Allow remote connections
echo "host all all 10.0.0.0/8 md5" >> /var/lib/pgsql/data/pg_hba.conf
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf
systemctl enable postgresql && systemctl start postgresql
# Create CDC user with SUPERUSER (required for Debezium publication creation)
sudo -u postgres psql -c "CREATE USER debezium WITH PASSWORD 'debezium' SUPERUSER REPLICATION LOGIN;"
sudo -u postgres psql -c "CREATE DATABASE ecommerce OWNER debezium;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ecommerce TO debezium;"
