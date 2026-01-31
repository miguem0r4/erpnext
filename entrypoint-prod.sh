#!/bin/bash
set -e
set -o pipefail

# Variables de entorno
SITE_DOMAIN="site1.localhost"
PORT=${PORT:-8000}
FRAPPE_VERSION=${FRAPPE_VERSION:-version-15}

echo "=== ERPNext Production Ready ==="
echo "Sitio: ${SITE_DOMAIN}"
echo "Puerto: ${PORT}"
echo "Versión: ${FRAPPE_VERSION}"
echo "================================"

# Función para verificar servicio
wait_for_db() {
    echo "🔍 Verificando conexión a base de datos..."
    for i in {1..30}; do
        if mysqladmin ping -h"${DB_HOST}" -P"${DB_PORT:-3306}" -u"${DB_USER}" -p"${DB_PASSWORD}" --silent 2>/dev/null; then
            echo "✅ Base de datos conectada"
            return 0
        fi
        echo "Intento $i/30: Esperando base de datos..."
        sleep 2
    done
    echo "❌ Error: No se puede conectar a la base de datos"
    exit 1
}

# Ir al directorio de trabajo
cd /home/frappe

# Limpiar y recrear si es necesario (para asegurar funcionamiento)
if [ -d "frappe-bench" ]; then
    echo "🧹 Limpiando bench existente..."
    rm -rf frappe-bench
fi

echo "🚀 Creando bench nuevo..."
bench init --frappe-branch ${FRAPPE_VERSION} frappe-bench

cd frappe-bench

echo "📦 Instalando aplicaciones..."
bench get-app --branch ${FRAPPE_VERSION} erpnext https://github.com/frappe/erpnext.git

# Crear sitio si no existe
if [ ! -d "sites/${SITE_DOMAIN}" ]; then
    echo "🌐 Creando sitio ${SITE_DOMAIN}..."
    
    # Esperar a que la base de datos esté lista
    wait_for_db
    
    bench new-site ${SITE_DOMAIN} \
        --db-name "${DB_NAME}" \
        --db-host "${DB_HOST}" \
        --db-port "${DB_PORT:-3306}" \
        --mariadb-user-host-login-scope='%' \
        --admin-password "${ADMIN_PASSWORD:-admin}" \
        --install-app erpnext \
        --no-mariadb-socket
fi

# Migrar si es necesario
echo "🔄 Ejecutando migraciones..."
bench --site ${SITE_DOMAIN} migrate --skip-failing

# Construir assets si es necesario
echo "🔨 Construyendo assets..."
bench build --app erpnext

# Iniciar servidor
echo "🚀 Iniciando servidor en puerto ${PORT}..."
exec bench --site ${SITE_DOMAIN} serve --port ${PORT} --host 0.0.0.0 --noreload