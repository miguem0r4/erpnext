#!/bin/bash
set -e

echo "=== ERPNext Version Optimizada ==="
echo "Sitio: site1.localhost"
echo "Puerto: $PORT"
echo "================================"

# Variables
SITE_DOMAIN="site1.localhost"
BENCH_DIR="/home/frappe/frappe-bench"

# Ir al directorio home
cd /home/frappe

# Optimizar instalación si no existe
if [ ! -d "frappe-bench" ]; then
    echo "🚀 Creando bench optimizado..."
    bench init --frappe-branch version-15 frappe-bench
    
    cd frappe-bench
    
    echo "📦 Instalando apps esenciales..."
    bench get-app --branch version-15 frappe https://github.com/frappe/frappe.git
    bench get-app --branch version-15 erpnext https://github.com/frappe/erpnext.git
    
    # Instalar dependencias más rápido
    echo "⚡ Instalando dependencias..."
    bench setup requirements --dev
else
    cd frappe-bench
    echo "✅ Bench existente encontrado"
fi

echo "🌐 Creando sitio..."
bench new-site ${SITE_DOMAIN} \
    --db-name "${DB_NAME}" \
    --db-host "${DB_HOST}" \
    --db-port "${DB_PORT:-3306}" \
    --mariadb-user-host-login-scope='%' \
    --admin-password "${ADMIN_PASSWORD:-admin}" \
    --install-app erpnext \
    --yes \
    --mariadb-root-password "root_password"

echo "🔨 Construyendo assets optimizados..."
bench build --app erpnext

echo "⚙️ Configurando sitio..."
bench --site ${SITE_DOMAIN} set-maintenance-mode off
bench --site ${SITE_DOMAIN} clear-cache

echo "🚀 Iniciando servidor optimizado..."
exec bench --site ${SITE_DOMAIN} serve --port ${PORT:-8000} --host 0.0.0.0 --no-reload --develop