#!/bin/sh

# set environment variables for UID and GID
PUID=${UID:-99}
PGID=${GID:-100}

# create a user and group with specified UID and GID
addgroup -g "$PGID" appgroup 2>/dev/null || true
adduser -D -u "$PUID" -G appgroup appuser 2>/dev/null || true

mkdir -p "$APP_HOME"
chown -R appuser:appgroup "$APP_HOME"

echo "Starting with UID: $PUID, GID: $PGID"

# Fix permissions
chown -R "$PUID":"$PGID" /config /input /output 2>/dev/null || true

until cd /home/app/web
do
    echo "Waiting for server volume..."
    sleep 1
done

until python manage.py migrate
do
    echo "Waiting for db to be ready..."
    sleep 2
done

python manage.py collectstatic --noinput

# Start Celery Worker
su-exec "$PUID:$PGID" celery -A bragibooks_proj worker \
    --loglevel=info \
    --concurrency "${CELERY_WORKERS:-1}" \
    -E &

# Start gunicorn server
su-exec "$PUID:$PGID" gunicorn bragibooks_proj.wsgi \
    --bind 0.0.0.0:8000 \
    --timeout 1200 \
    --worker-tmp-dir /dev/shm \
    --workers 2 \
    --threads 4 \
    --worker-class gthread \
    --enable-stdio-inheritance
