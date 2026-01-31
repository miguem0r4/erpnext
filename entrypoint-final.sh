#!/bin/bash
set -e

echo "=== ERPNext Version Final ==="
echo "Sitio: site1.localhost"
echo "Puerto: $PORT"
echo "================================"

# Variables
SITE_DOMAIN="site1.localhost"
BENCH_DIR="/home/frappe/frappe-bench"

# Ir al directorio home
cd /home/frappe

# Crear bench desde cero
echo "🚀 Creando bench..."
if [ -d "frappe-bench" ]; then
    echo "Eliminando bench existente..."
    rm -rf frappe-bench
fi
bench init --frappe-branch version-15 frappe-bench

cd frappe-bench

echo "📦 Instalando ERPNext..."
bench get-app --branch version-15 erpnext https://github.com/frappe/erpnext.git

echo "🌐 Creando sitio..."
bench new-site ${SITE_DOMAIN} \
    --db-name "${DB_NAME}" \
    --db-host "${DB_HOST}" \
    --db-port "${DB_PORT:-3306}" \
    --mariadb-user-host-login-scope='%' \
    --admin-password "${ADMIN_PASSWORD:-admin}" \
    --install-app erpnext \
    --yes

echo "🔨 Construyendo assets..."
bench build

echo "⚙️ Configurando sitio..."
bench --site ${SITE_DOMAIN} set-maintenance-mode off

echo "🚀 Iniciando servidor..."
exec bench --site ${SITE_DOMAIN} serve --port ${PORT:-8000} --host 0.0.0.0 --no-reload