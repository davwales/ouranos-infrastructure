#!/bin/bash
set -e

IFS=',' read -ra DATABASES <<< "$INIT_DATABASES"

for db in "${DATABASES[@]}"; do
  db=$(echo "$db" | xargs)
  
  echo "Checking/Creating database: $db"

  psql -h postgres -U "$PGUSER" -d postgres <<EOSQL
    SELECT 'CREATE DATABASE "$db"' 
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec

    SELECT 'GRANT ALL PRIVILEGES ON DATABASE "$db" TO "$PGUSER"' 
    WHERE EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
EOSQL

done