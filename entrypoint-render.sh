#!/bin/bash
set -e

echo "=== ERPNext Simplificado para Render ==="
echo "Sitio: site1.localhost"
echo "Puerto: $PORT"
echo "================================"

# Variables
SITE_DOMAIN="site1.localhost"
BENCH_DIR="/home/frappe/frappe-bench"

# Ir al directorio home
cd /home/frappe

# Siempre recrear el bench limpio (para Render)
echo "🚀 Inicializando bench..."
rm -rf frappe-bench
bench init --frappe-branch version-15 --skip-assets frappe-bench

cd frappe-bench

echo "📦 Instalando aplicaciones..."
bench get-app --branch version-15 erpnext https://github.com/frappe/erpnext.git

echo "🌐 Creando sitio..."
bench new-site ${SITE_DOMAIN} \
    --db-name "${DB_NAME}" \
    --db-host "${DB_HOST}" \
    --db-port "${DB_PORT:-3306}" \
    --db-root-username "${DB_USER}" \
    --db-password "${DB_PASSWORD}" \
    --admin-password "${ADMIN_PASSWORD:-admin}" \
    --install-app erpnext \
    --no-mariadb-socket

echo "🔨 Construyendo..."
bench build --app erpnext

echo "🚀 Iniciando servidor..."
exec bench --site ${SITE_DOMAIN} serve --port ${PORT:-8000} --host 0.0.0.0