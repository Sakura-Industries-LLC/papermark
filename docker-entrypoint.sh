#!/bin/sh
set -eu

echo "Papermark: waiting for PostgreSQL..."

MAX_RETRIES=30
RETRY_INTERVAL=2
RETRIES=0

# Extract host and port from DATABASE_URL.
# Format: postgresql://user:pass@host:port/dbname
DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*@\([^:/]*\).*|\1|p')
DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
DB_PORT=${DB_PORT:-5432}

# TCP check using Node.js (guaranteed available in this image).
tcp_check() {
    node -e "
        const s = require('net').connect(${DB_PORT}, '${DB_HOST}');
        s.on('connect', () => { s.destroy(); process.exit(0); });
        s.on('error', () => process.exit(1));
        setTimeout(() => process.exit(1), 2000);
    " 2>/dev/null
}

while ! tcp_check && [ $RETRIES -lt $MAX_RETRIES ]; do
    RETRIES=$((RETRIES + 1))
    echo "  Attempt $RETRIES/$MAX_RETRIES — waiting ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

if [ $RETRIES -ge $MAX_RETRIES ]; then
    echo "ERROR: PostgreSQL not ready after $((MAX_RETRIES * RETRY_INTERVAL))s"
    exit 1
fi

echo "Papermark: PostgreSQL is ready. Syncing database schema..."
node ./node_modules/prisma/build/index.js db push --skip-generate

echo "Papermark: starting server..."
exec node server.js
