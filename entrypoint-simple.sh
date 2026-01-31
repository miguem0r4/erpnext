#!/bin/bash
set -e
set -o pipefail

# Variables de entorno
SITE_NAME=${SITE_NAME:-erpnext}
PORT=${PORT:-8000}
FRAPPE_VERSION=${FRAPPE_VERSION:-version-15}

echo "=== Configuración ERPNext ==="
echo "Sitio: ${SITE_NAME}"
echo "Puerto: ${PORT}"
echo "Versión Frappe: ${FRAPPE_VERSION}"
echo "================================"

# Verificar que redis-server esté disponible
if ! command -v redis-server &> /dev/null; then
    echo "ERROR: redis-server no está disponible"
    exit 1
fi

# Verificar que yarn esté disponible
if ! command -v yarn &> /dev/null; then
    echo "ERROR: yarn no está disponible"
    exit 1
fi

# Iniciar Redis local si no hay REDIS_URL
if [ -z "$REDIS_URL" ]; then
    echo "Iniciando Redis local..."
    redis-server --daemonize yes --port 6379 --save "" --appendonly no
    export REDIS_URL="redis://127.0.0.1:6379"
fi

# Directorio del bench
BENCH_DIR="/home/frappe/frappe-bench"

# Siempre asegurarse de que el bench esté correctamente inicializado
cd /home/frappe
if [ ! -d "$BENCH_DIR" ] || [ ! -f "$BENCH_DIR/apps/frappe/__init__.py" ]; then
    echo "Creando/Reinicializando bench..."
    rm -rf frappe-bench
    bench init --frappe-branch ${FRAPPE_VERSION} frappe-bench
    cd frappe-bench
    
    echo "Instalando aplicaciones..."
    bench get-app --branch ${FRAPPE_VERSION} erpnext https://github.com/frappe/erpnext.git
else
    echo "Bench existente encontrado"
    cd "$BENCH_DIR"
fi

# Crear sitio si no existe (usar nombre diferente al app)
SITE_DOMAIN="site1.localhost"
if [ ! -d "sites/${SITE_DOMAIN}" ]; then
    echo "Creando sitio ${SITE_DOMAIN}..."
    
    # Verificar configuración de base de datos
    if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
        echo "ERROR: Faltan variables de base de datos"
        exit 1
    fi
    
    bench new-site ${SITE_DOMAIN} \
        --db-name "${DB_NAME}" \
        --db-host "${DB_HOST}" \
        --db-port "${DB_PORT:-3306}" \
        --mariadb-user-host-login-scope='%' \
        --admin-password "${ADMIN_PASSWORD:-admin}" \
        --install-app erpnext
fi

# Migrar y construir
echo "Ejecutando migraciones..."
bench --site ${SITE_DOMAIN} migrate

echo "Construyendo assets..."
bench build

# Iniciar servidor
echo "Iniciando servidor en puerto ${PORT}..."
exec bench --site ${SITE_DOMAIN} serve --port ${PORT} --host 0.0.0.0 --noreload