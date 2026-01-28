#!/bin/bash
set -e

# Variables de entorno requeridas (Render las proporcionará)
# DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
# REDIS_URL
# SITE_NAME (opcional, default: erpnext)
# WORKER_MODE (opcional, si está definido, ejecuta worker en lugar del servidor web)

SITE_NAME=${SITE_NAME:-erpnext}
PORT=${PORT:-8000}

# Si WORKER_MODE está definido, ejecutar worker
if [ ! -z "$WORKER_MODE" ]; then
    echo "Modo worker activado"
    cd /home/frappe/frappe-bench
    exec bench --site ${SITE_NAME} worker
fi

# Inicializar bench si no existe
if [ ! -d "/home/frappe/frappe-bench" ]; then
    echo "Inicializando bench..."
    cd /home/frappe
    bench init --skip-assets --frappe-branch version-17 frappe-bench
fi

cd /home/frappe/frappe-bench

# Obtener Frappe si no existe
if [ ! -d "apps/frappe" ]; then
    echo "Obteniendo Frappe Framework..."
    bench get-app --branch version-17 frappe https://github.com/frappe/frappe.git || true
fi

# Obtener ERPNext si no existe
if [ ! -d "apps/erpnext" ]; then
    echo "Obteniendo ERPNext..."
    bench get-app --branch version-17 erpnext https://github.com/frappe/erpnext.git || true
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
echo "Iniciando servidor en puerto ${PORT}..."
exec bench --site ${SITE_NAME} serve --port ${PORT} --host 0.0.0.0
