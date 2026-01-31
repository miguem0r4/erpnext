#!/bin/bash
set -e
set -o pipefail

# Variables de entorno
SITE_DOMAIN="site1.localhost"
PORT=${PORT:-8000}
FRAPPE_VERSION=${FRAPPE_VERSION:-version-15}

echo "=== ERPNext Optimizado ==="
echo "Sitio: ${SITE_DOMAIN}"
echo "Puerto: ${PORT}"
echo "Versión: ${FRAPPE_VERSION}"
echo "==========================="

# Directorio del bench
BENCH_DIR="/home/frappe/frappe-bench"
cd /home/frappe

# Solo inicializar si el bench no existe
if [ ! -d "$BENCH_DIR" ]; then
    echo "🚀 Inicializando bench por primera vez..."
    bench init --frappe-branch ${FRAPPE_VERSION} --skip-apps frappe-bench
    cd frappe-bench
    
    echo "📦 Instalando Frappe..."
    bench get-app --branch ${FRAPPE_VERSION} frappe https://github.com/frappe/frappe.git
    
    echo "📦 Instalando ERPNext..."
    bench get-app --branch ${FRAPPE_VERSION} erpnext https://github.com/frappe/erpnext.git
    
    echo "🔧 Configurando bench..."
    bench setup Procfile
    bench setup config
    
    # Configurar Redis local
    bench set-config -g redis_cache "redis://127.0.0.1:13000"
    bench set-config -g redis_queue "redis://127.0.0.1:11000"
    bench set-config -g redis_socketio "redis://127.0.0.1:12000"
    
    # Crear archivo de inicialización completada
    touch .bench_initialized
    
    echo "✅ Bench inicializado correctamente"
else
    cd "$BENCH_DIR"
fi

# Crear sitio si no existe
if [ ! -d "sites/${SITE_DOMAIN}" ]; then
    echo "🌐 Creando sitio ${SITE_DOMAIN}..."
    
    # Verificar configuración de base de datos
    if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
        echo "❌ Error: Faltan variables de base de datos"
        exit 1
    fi
    
    bench new-site ${SITE_DOMAIN} \
        --db-name "${DB_NAME}" \
        --db-host "${DB_HOST}" \
        --db-port "${DB_PORT:-3306}" \
        --mariadb-user-host-login-scope='%' \
        --admin-password "${ADMIN_PASSWORD:-admin}" \
        --install-app erpnext \
        --no-mariadb-socket
    
    echo "✅ Sitio creado correctamente"
fi

# Ejecutar migraciones y build solo si es necesario
if [ -f ".bench_initialized" ] && [ ! -f ".site_ready_${SITE_DOMAIN}" ]; then
    echo "🔄 Ejecutando migraciones..."
    bench --site ${SITE_DOMAIN} migrate
    
    echo "🔨 Construyendo assets..."
    bench build --app frappe
    bench build --app erpnext
    
    # Marcar sitio como listo
    touch ".site_ready_${SITE_DOMAIN}"
    echo "✅ Sitio configurado correctamente"
fi

# Iniciar servidor
echo "🚀 Iniciando servidor en puerto ${PORT}..."
exec bench --site ${SITE_DOMAIN} serve --port ${PORT} --host 0.0.0.0 --noreload --with-reloader