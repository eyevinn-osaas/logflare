#!/bin/bash

if [[ ! -z "${OSC_HOSTNAME}" ]]; then
  export LOGFLARE_NODE_HOST="${OSC_HOSTNAME}"
fi

export LOGFLARE_SINGLE_TENANT="true"
export PHX_HTTP_PORT="${PORT:-8080}"

if [[ -z "${POSTGRES_BACKEND_URL}" ]]; then
  echo "POSTGRES_BACKEND_URL is not set. Exiting..."
  exit 1
fi

PG_URL="${POSTGRES_BACKEND_URL}"
PG_PROTOCOL="${PG_URL%%://*}"
PG_REMAINDER="${PG_URL#*://}"
PG_CREDS_HOST="${PG_REMAINDER%%/*}"
DB_DATABASE="${PG_REMAINDER#*/}"

# Extract credentials and host separately
if [[ "$PG_CREDS_HOST" == *"@"* ]]; then
  PG_CREDS="${PG_CREDS_HOST%%@*}"
  PG_HOST="${PG_CREDS_HOST#*@}"
  
  # Extract username and password
  if [[ "$PG_CREDS" == *":"* ]]; then
    DB_USERNAME="${PG_CREDS%%:*}"
    DB_PASSWORD="${PG_CREDS#*:}"
  else
    DB_USERNAME="$PG_CREDS"
    DB_PASSWORD=""
  fi
else
  PG_HOST="$PG_CREDS_HOST"
  DB_USERNAME=""
  DB_PASSWORD=""
fi

# Extract host and port
if [[ "$PG_HOST" == *":"* ]]; then
  DB_HOSTNAME="${PG_HOST%%:*}"
  DB_PORT="${PG_HOST#*:}"
else
  DB_HOSTNAME="$PG_HOST"
  DB_PORT="5432" # Default PostgreSQL port
fi

export DB_DATABASE DB_HOSTNAME DB_PORT DB_USERNAME DB_PASSWORD
exec "$@"
