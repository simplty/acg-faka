#!/bin/bash
# Usage: ./debug/apply.sh
# Copies debug nginx config into container and reloads, then runs curl test

CONTAINER="aihub-shop"

docker cp debug/nginx-debug.conf "$CONTAINER":/etc/nginx/sites-available/default
docker exec "$CONTAINER" nginx -s reload
echo "=== curl -v http://127.0.0.1:3080/test.php ==="
curl -v http://127.0.0.1:3080/test.php 2>&1
