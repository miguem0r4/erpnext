#!/bin/bash
set -e

echo "=== ERPNext Production Entrypoint ==="
echo "Site: ${SITE_NAME:-erpnext}"
echo "Port: ${PORT:-10000}"
echo "================================"

# Variables
SITE_NAME=${SITE_NAME:-erpnext}
BENCH_DIR="/home/frappe/frappe-bench"
PERSISTENT_DIR="/home/frappe/bench-data"

# Crear directorio persistente si no existe
mkdir -p $PERSISTENT_DIR

# Verificar Redis y yarn
echo "Verificando dependencias..."
command -v redis-server >/dev/null 2>&1 || { echo "ERROR: redis-server not found"; exit 1; }
command -v yarn >/dev/null 2>&1 || { echo "ERROR: yarn not found"; exit 1; }

# Si existe un bench persistente, restaurarlo
if [ -d "$PERSISTENT_DIR/frappe-bench" ] && [ -f "$PERSISTENT_DIR/frappe-bench/bench/config.json" ]; then
    echo "🔄 Restaurando bench desde volumen persistente..."
    if [ ! -L "$BENCH_DIR" ]; then
        rm -rf "$BENCH_DIR" 2>/dev/null || true
        ln -sf "$PERSISTENT_DIR/frappe-bench" "$BENCH_DIR"
    fi
    cd "$BENCH_DIR"
    echo "✅ Bench restaurado"
elif [ -d "$BENCH_DIR" ] && [ -f "$BENCH_DIR/bench/config.json" ]; then
    echo "✅ Bench existente encontrado"
    cd "$BENCH_DIR"
    # Hacer backup al volumen persistente
    if [ ! -d "$PERSISTENT_DIR/frappe-bench" ]; then
        echo "💾 Haciendo backup del bench actual..."
        cp -r "$BENCH_DIR" "$PERSISTENT_DIR/frappe-bench"
    fi
else
    echo "🚀 Creando nuevo bench..."
    cd /home/frappe
    
    # Inicializar bench
    bench init --frappe-branch version-15 --skip-assets frappe-bench
    
    cd frappe-bench
    
    # Instalar apps
    echo "📦 Instalando Frappe..."
    bench get-app --branch version-15 frappe https://github.com/frappe/frappe.git
    
    echo "📦 Instalando ERPNext..."
    bench get-app --branch version-15 erpnext https://github.com/frappe/erpnext.git
    
    # Crear sitio solo si no existe en DB
    if [ ! -d "sites/$SITE_NAME" ]; then
        echo "🌐 Creando sitio $SITE_NAME..."
        bench new-site $SITE_NAME \
            --db-name "${DB_NAME}" \
            --db-host "${DB_HOST}" \
            --db-port "${DB_PORT:-3306}" \
            --mariadb-user-host-login-scope='%' \
            --admin-password "${ADMIN_PASSWORD:-admin}" \
            --install-app erpnext \
            --yes
    fi
    
    # Hacer backup persistente
    echo "💾 Guardando bench en volumen persistente..."
    cp -r /home/frappe/frappe-bench "$PERSISTENT_DIR/frappe-bench"
fi

# Compilar assets solo si es necesario
if [ ! -f "sites/$SITE_NAME/assets/erpnext/css/erpnext.bundle.css" ]; then
    echo "🔨 Compilando assets..."
    bench build --app erpnext
else
    echo "✅ Assets ya existen"
fi

# Limpiar cache
bench --site $SITE_NAME clear-cache

# Iniciar servidor
echo "🚀 Iniciando servidor ERPNext..."
echo "URL: https://erpnext-web-a68i.onrender.com"
echo "================================"

exec bench --site $SITE_NAME serve --port ${PORT:-10000} --host 0.0.0.0 --noreload