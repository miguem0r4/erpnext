#!/bin/bash
set -e

# Variables de entorno requeridas (Render las proporcionará)
# DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
# REDIS_URL (opcional, si no se proporciona se usa Redis local)
# SITE_NAME (opcional, default: erpnext)
# FRAPPE_VERSION (opcional, default: version-15 - versiones válidas: version-14, version-15, version-16, develop)
# Nota: version-16 requiere Python 3.14+ que aún no está disponible en Docker
# WORKER_MODE (opcional, si está definido, ejecuta worker en lugar del servidor web)

SITE_NAME=${SITE_NAME:-erpnext}
# PORT: Render proporciona automáticamente esta variable (default: 10000)
# Es crítico usar esta variable y escuchar en 0.0.0.0 para que Render pueda enrutar el tráfico
PORT=${PORT:-10000}
# Por defecto usar version-15 (compatible con Python 3.12)
# version-16 requiere Python 3.14+ que aún no está disponible en imágenes Docker oficiales
FRAPPE_VERSION=${FRAPPE_VERSION:-version-15}

# Verificar que redis-server esté disponible
if ! command -v redis-server &> /dev/null; then
    echo "ERROR: redis-server no está disponible en el PATH"
    echo "PATH actual: $PATH"
    echo "Buscando redis-server..."
    find /usr -name redis-server 2>/dev/null || echo "redis-server no encontrado"
    exit 1
fi

# Verificar versión de Redis (necesario para bench init)
echo "Verificando Redis..."
redis-server --version || echo "Advertencia: No se pudo obtener versión de Redis"

# Verificar que yarn esté disponible (requerido por Frappe)
if ! command -v yarn &> /dev/null; then
    echo "ERROR: yarn no está disponible en el PATH"
    echo "PATH actual: $PATH"
    echo "Buscando yarn..."
    find /usr -name yarn 2>/dev/null || echo "yarn no encontrado"
    exit 1
fi
echo "Verificando yarn..."
yarn --version || echo "Advertencia: No se pudo obtener versión de yarn"

# Iniciar Redis local si no hay REDIS_URL (modo local)
# Nota: En Render, normalmente se proporciona REDIS_URL
if [ -z "$REDIS_URL" ]; then
    echo "REDIS_URL no configurado, iniciando Redis local..."
    # Crear directorios necesarios
    mkdir -p /home/frappe/redis-data /home/frappe/redis-logs
    # Iniciar Redis en background con configuración mínima
    redis-server --daemonize yes \
        --dir /home/frappe/redis-data \
        --logfile /home/frappe/redis-logs/redis.log \
        --port 6379 \
        --bind 127.0.0.1 \
        --save "" \
        --appendonly no || echo "Redis ya está ejecutándose o error al iniciar"
    export REDIS_URL="redis://127.0.0.1:6379"
    echo "Redis local configurado en 127.0.0.1:6379"
    sleep 2  # Dar tiempo a Redis para iniciar
else
    echo "Usando Redis externo: $REDIS_URL"
fi

# Si WORKER_MODE está definido, ejecutar worker
if [ ! -z "$WORKER_MODE" ]; then
    echo "Modo worker activado"
    cd /home/frappe/frappe-bench
    exec bench --site ${SITE_NAME} worker
fi

# Inicializar bench si no existe
if [ ! -d "/home/frappe/frappe-bench" ]; then
    echo "Inicializando bench con Frappe ${FRAPPE_VERSION}..."
    cd /home/frappe
    
    # Crear directorios temporales para supervisor si no existen
    mkdir -p /tmp/supervisor/run /tmp/supervisor/log 2>/dev/null || true
    
    # Inicializar bench con manejo robusto de errores
    # bench init puede fallar en supervisor/cron, pero el bench se crea antes de eso
    echo "Ejecutando bench init (puede mostrar warnings sobre supervisor/cron)..."
    
    # Ejecutar bench init y capturar salida
    if bench init --skip-assets --frappe-branch ${FRAPPE_VERSION} frappe-bench 2>&1 | tee /tmp/bench-init.log; then
        echo "✅ Bench inicializado correctamente"
    else
        INIT_EXIT=$?
        # Verificar si el bench se creó a pesar del error
        if [ -d "frappe-bench" ]; then
            # El bench existe, probablemente fue un error de supervisor/cron
            if grep -qE "(crontab|supervisor|/usr/bin/crontab)" /tmp/bench-init.log 2>/dev/null; then
                echo "⚠️  Advertencia: bench init tuvo problemas con supervisor/cron (esperado en Render)"
                echo "✅ El bench se creó correctamente, continuando..."
            else
                echo "⚠️  Advertencia: bench init tuvo algunos errores, pero el bench existe"
                echo "Últimas líneas del log:"
                tail -10 /tmp/bench-init.log
            fi
        else
            echo "❌ ERROR: bench init falló completamente. Logs:"
            cat /tmp/bench-init.log
            exit $INIT_EXIT
        fi
    fi
fi

cd /home/frappe/frappe-bench

# Obtener Frappe si no existe
if [ ! -d "apps/frappe" ]; then
    echo "Obteniendo Frappe Framework (${FRAPPE_VERSION})..."
    bench get-app --branch ${FRAPPE_VERSION} frappe https://github.com/frappe/frappe.git || true
fi

# Obtener ERPNext si no existe
if [ ! -d "apps/erpnext" ]; then
    echo "Obteniendo ERPNext (${FRAPPE_VERSION})..."
    bench get-app --branch ${FRAPPE_VERSION} erpnext https://github.com/frappe/erpnext.git || true
fi

# Si el sitio no existe, crearlo
if [ ! -d "sites/${SITE_NAME}" ]; then
    echo "Creando nuevo sitio: ${SITE_NAME}"
    
    # Crear el sitio
    bench new-site ${SITE_NAME} \
        --db-name ${DB_NAME} \
        --db-host ${DB_HOST} \
        --db-port ${DB_PORT} \
        --db-user ${DB_USER} \
        --db-password ${DB_PASSWORD} \
        --admin-password "${ADMIN_PASSWORD:-admin}" \
        --no-mariadb-socket \
        --install-app erpnext || echo "Sitio ya existe o error en creación"
fi

# Actualizar configuración del sitio
if [ -f "sites/${SITE_NAME}/site_config.json" ]; then
    echo "Actualizando configuración del sitio..."
    python3 <<PYTHON
import json
import os

config_path = "sites/${SITE_NAME}/site_config.json"
with open(config_path, 'r') as f:
    config = json.load(f)

config['db_name'] = os.getenv('DB_NAME', config.get('db_name'))
config['db_host'] = os.getenv('DB_HOST', config.get('db_host'))
config['db_port'] = os.getenv('DB_PORT', config.get('db_port'))
config['db_user'] = os.getenv('DB_USER', config.get('db_user'))
config['db_password'] = os.getenv('DB_PASSWORD', config.get('db_password'))
config['redis_cache'] = os.getenv('REDIS_URL', config.get('redis_cache'))
config['redis_queue'] = os.getenv('REDIS_URL', config.get('redis_queue'))
config['redis_socketio'] = os.getenv('REDIS_URL', config.get('redis_socketio'))

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
PYTHON
fi

# Migrar base de datos si es necesario
echo "Ejecutando migraciones..."
bench --site ${SITE_NAME} migrate || true

# Compilar assets si es necesario
echo "Compilando assets..."
bench build --app erpnext || true
bench --site ${SITE_NAME} clear-cache || true

# Iniciar el servidor
# IMPORTANTE: Render requiere que el servidor escuche en 0.0.0.0 (todas las interfaces)
# y use la variable PORT proporcionada por Render para el binding correcto
echo "=========================================="
echo "Iniciando servidor ERPNext"
echo "Puerto: ${PORT} (proporcionado por Render)"
echo "Host: 0.0.0.0 (requerido por Render)"
echo "=========================================="

# Validar que PORT esté definido
if [ -z "$PORT" ]; then
    echo "ERROR: PORT no está definido. Render debe proporcionar esta variable."
    exit 1
fi

# Iniciar el servidor - CRÍTICO: debe escuchar en 0.0.0.0:${PORT}
exec bench --site ${SITE_NAME} serve --port ${PORT} --host 0.0.0.0 --noreload
