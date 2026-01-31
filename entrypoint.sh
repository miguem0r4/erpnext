#!/bin/bash
set -e
set -o pipefail

# Variables de entorno requeridas (Render las proporcionará)
# DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
# REDIS_URL (opcional, si no se proporciona se usa Redis local)
# SITE_NAME (opcional, default: erpnext)
# FRAPPE_VERSION (opcional, default: version-15 - versiones válidas: version-14, version-15, version-16, develop)
# Nota: version-16 requiere Python 3.14+ que aún no está disponible en Docker
# WORKER_MODE (opcional, si está definido, ejecuta worker en lugar del servidor web)

SITE_NAME=${SITE_NAME:-mi-erpnext}
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

# Directorio del bench (puede ser un volumen montado vacío)
BENCH_DIR="/home/frappe/frappe-bench"
# Bench válido = tiene apps/ y sites/ (creados por bench init)
is_valid_bench() {
    [ -d "${BENCH_DIR}/apps" ] && [ -d "${BENCH_DIR}/sites" ]
}

# Inicializar bench si no existe o está vacío (volumen montado sin contenido)
if ! is_valid_bench; then
    echo "Inicializando bench con Frappe ${FRAPPE_VERSION}..."
    cd /home/frappe
    mkdir -p /tmp/supervisor/run /tmp/supervisor/log 2>/dev/null || true

    # Si el directorio existe pero está vacío o con restos (volumen Docker), limpiar y usar symlink
    if [ -d "$BENCH_DIR" ]; then
        echo "Directorio bench existe (volumen), limpiando restos de intentos anteriores..."
        find "$BENCH_DIR" -mindepth 1 -delete 2>/dev/null || true
        echo "Inicializando con symlink..."
        rm -rf /tmp/bench-init 2>/dev/null || true
        ln -s "$BENCH_DIR" /tmp/bench-init
        run_bench_init() {
            bench init --skip-assets --frappe-branch ${FRAPPE_VERSION} /tmp/bench-init 2>&1 | tee /tmp/bench-init.log
        }
        if run_bench_init; then
            echo "✅ Bench inicializado en volumen"
        else
            INIT_EXIT=$?
            if is_valid_bench; then
                echo "✅ Bench creado (warnings ignorados), continuando..."
            else
                echo "❌ ERROR: bench init falló. Logs:"
                cat /tmp/bench-init.log
                exit $INIT_EXIT
            fi
        fi
        # No eliminar el symlink: el venv usa rutas /tmp/bench-init/... que deben seguir resolviendo
    else
        echo "Ejecutando bench init frappe-bench..."
        if bench init --skip-assets --frappe-branch ${FRAPPE_VERSION} frappe-bench 2>&1 | tee /tmp/bench-init.log; then
            echo "✅ Bench inicializado correctamente"
        else
            INIT_EXIT=$?
            if [ -d "frappe-bench/apps" ] && [ -d "frappe-bench/sites" ]; then
                echo "✅ Bench creado (warnings ignorados), continuando..."
            else
                echo "❌ ERROR: bench init falló. Logs:"
                cat /tmp/bench-init.log
                exit $INIT_EXIT
            fi
        fi
    fi
fi

# Usar la ruta con la que bench fue inicializado (symlink o real) para que "bench" reconozca el directorio
if [ -L /tmp/bench-init ] && [ -d /tmp/bench-init ]; then
    BENCH_CWD="/tmp/bench-init"
else
    BENCH_CWD="/home/frappe/frappe-bench"
fi
cd "$BENCH_CWD"
echo "Directorio de trabajo bench: $BENCH_CWD ($(pwd))"

# Verificar que estamos en un directorio bench válido
if [ ! -f "bench/config.json" ]; then
    echo "ERROR: No se encuentra en un directorio bench válido. Buscando directorio bench..."
    # Buscar directorio bench válido
    if [ -d "/home/frappe/frappe-bench" ] && [ -f "/home/frappe/frappe-bench/bench/config.json" ]; then
        BENCH_CWD="/home/frappe/frappe-bench"
        cd "$BENCH_CWD"
        echo "Usando directorio bench: $BENCH_CWD"
    elif [ -d "/tmp/bench-init" ] && [ -f "/tmp/bench-init/bench/config.json" ]; then
        BENCH_CWD="/tmp/bench-init"
        cd "$BENCH_CWD"
        echo "Usando directorio bench: $BENCH_CWD"
    else
        echo "ERROR: No se encontró un directorio bench válido"
        ls -la /home/frappe/
        ls -la /tmp/
        exit 1
    fi
fi

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
DETECTED_SITE_NAME=""
if [ -d "sites/${SITE_NAME}" ]; then
    DETECTED_SITE_NAME=${SITE_NAME}
    echo "El sitio ${SITE_NAME} ya existe en el directorio"
elif [ -d "sites/mysite" ]; then
    DETECTED_SITE_NAME="mysite"
    echo "Detectado sitio existente: mysite"
elif [ -d "sites/site1" ]; then
    DETECTED_SITE_NAME="site1"
    echo "Detectado sitio existente: site1"
fi

if [ -n "$DETECTED_SITE_NAME" ]; then
    SITE_NAME=${DETECTED_SITE_NAME}
    echo "Usando sitio existente: ${SITE_NAME}"
elif [ ! -d "sites/${SITE_NAME}" ]; then
    echo "Creando nuevo sitio: ${SITE_NAME}"

    # Verificar si el sitio ya existe en la base de datos
    SITE_EXISTS_DB=0
    if [ -n "$DB_HOST" ] && [ -n "$DB_NAME" ] && command -v mysql &> /dev/null; then
        echo "Verificando si el sitio ya existe en la base de datos..."
        if mysql -h "$DB_HOST" -P "${DB_PORT:-3306}" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SHOW TABLES LIKE 'tab__Site Config'" 2>/dev/null | grep -q "tab__Site Config"; then
            SITE_EXISTS_DB=1
            echo "El sitio ya existe en la base de datos"
        fi
    fi

    # Si el sitio existe en la DB, buscar un directorio existente o usar uno alternativo
    if [ "$SITE_EXISTS_DB" = "1" ]; then
        echo "El sitio ya existe en la base de datos, buscando directorio existente..."
        if [ -d "sites/mysite" ]; then
            SITE_NAME="mysite"
        elif [ -d "sites/site1" ]; then
            SITE_NAME="site1"
        else
            SITE_NAME="mysite"
        fi
        echo "Usando sitio existente: ${SITE_NAME}"
    else
        CREATED_SITE_NAME="${SITE_NAME}"
        if [ "${SITE_NAME}" = "erpnext" ]; then
            CREATED_SITE_NAME="mysite"
            echo "Usando nombre alternativo '${CREATED_SITE_NAME}' para evitar conflicto con la app"
        fi

        echo "=== Verificando configuración de base de datos ==="
        echo "DB_HOST: ${DB_HOST:-NO DEFINIDO}"
        echo "DB_PORT: ${DB_PORT:-NO DEFINIDO}"
        echo "DB_NAME: ${DB_NAME:-NO DEFINIDO}"
        echo "DB_USER: ${DB_USER:-NO DEFINIDO}"

        if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
            echo "ERROR: Faltan variables de entorno requeridas para la base de datos"
            echo "Asegúrate de tener configurado en Render:"
            echo "  - DB_HOST"
            echo "  - DB_PORT (usualmente 3306)"
            echo "  - DB_NAME"
            echo "  - DB_USER"
            echo "  - DB_PASSWORD"
            exit 1
        fi

        DB_PORT=${DB_PORT:-3306}
        export DB_PORT

        echo "=== Creando sitio ${CREATED_SITE_NAME} ==="
        if bench new-site ${CREATED_SITE_NAME} \
            --db-name "${DB_NAME}" \
            --db-host "${DB_HOST}" \
            --db-port "${DB_PORT}" \
            --db-root-username "${DB_USER}" \
            --db-password "${DB_PASSWORD}" \
            --admin-password "${ADMIN_PASSWORD:-admin}" \
            --no-mariadb-socket \
            --install-app erpnext 2>&1; then
            echo "Sitio creado exitosamente"

            if [ "${CREATED_SITE_NAME}" != "${SITE_NAME}" ]; then
                echo "Renombrando sitio de ${CREATED_SITE_NAME} a ${SITE_NAME}..."
                if bench rename-site ${CREATED_SITE_NAME} ${SITE_NAME} 2>&1; then
                    echo "Sitio renombrado exitosamente"
                else
                    echo "No se pudo renombrar, el sitio seguirá usando el nombre ${CREATED_SITE_NAME}"
                    SITE_NAME=${CREATED_SITE_NAME}
                fi
            fi
        else
            echo "ADVERTENCIA: Error al crear el sitio"
            if [ -d "sites/${CREATED_SITE_NAME}" ]; then
                echo "El sitio fue creado con nombre ${CREATED_SITE_NAME}"
                SITE_NAME=${CREATED_SITE_NAME}
            fi
        fi
    fi
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
exec bench --site ${SITE_NAME} serve --port ${PORT} --noreload
