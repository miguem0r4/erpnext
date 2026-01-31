#!/bin/bash
set -e

echo "=== ERPNext Lightweight Deployment ==="
echo "Sitio: erpnext"
echo "Puerto: $PORT"
echo "Memoria límite: 2GB"
echo "================================"

# Variables
SITE_DOMAIN="erpnext"
BENCH_DIR="/home/frappe/frappe-bench"

# Ir al directorio home
cd /home/frappe

# Optimizar entorno para bajo consumo de recursos
export FRAPPE_PRODUCTION=1
export WORKERS=2
export FRAPPE_SERVER_TIMEOUT=60
export NO_CHROME=1

# Si ya existe, iniciar directamente
if [ -d "frappe-bench" ] && [ -d "frappe-bench/sites/${SITE_DOMAIN}" ]; then
    echo "✅ Bench existente encontrado, iniciando servidor..."
    cd frappe-bench
    echo "🚀 Iniciando servidor ligero..."
    exec bench --site ${SITE_DOMAIN} serve --port ${PORT:-8000} --host 0.0.0.0 --workers 2 --no-reload
else
    echo "🚀 Creando bench optimizado..."
    # Crear bench sin apps innecesarias
    bench init --frappe-branch version-15 frappe-bench
    
    cd frappe-bench
    
    echo "📦 Instalando solo ERPNext esencial..."
    # Solo instalar ERPNext sin dependencias pesadas
    bench get-app --branch version-15 erpnext https://github.com/frappe/erpnext.git --resolve-deps
    
    echo "🌐 Creando sitio con configuración ligera..."
    bench new-site ${SITE_DOMAIN} \
        --db-name "${DB_NAME}" \
        --db-host "${DB_HOST}" \
        --db-port "${DB_PORT:-3306}" \
        --mariadb-user-host-login-scope='%' \
        --admin-password "${ADMIN_PASSWORD:-admin}" \
        --install-app erpnext \
        --yes \
        --mariadb-root-password "root_password" \
        --verbose
    
    echo "🔨 Construyendo solo assets necesarios..."
    # Build optimizado
    bench build --app erpnext
    
    echo "⚙️ Optimizando configuración..."
    # Configurar producción
    bench --site ${SITE_DOMAIN} set-maintenance-mode off
    bench --site ${SITE_DOMAIN} clear-cache
    
    # Configurar para bajo consumo
    bench --site ${SITE_DOMAIN} set-config "server_timeout" 60
    bench --site ${SITE_DOMAIN} set-config "workers" 2
    
    echo "🚀 Iniciando servidor ligero..."
    exec bench --site ${SITE_DOMAIN} serve --port ${PORT:-8000} --host 0.0.0.0 --workers 2 --no-reload
fi