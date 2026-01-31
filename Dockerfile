# Dockerfile para ERPNext en Render.com
# Basado en Frappe Framework y optimizado para producción
#
# IMPORTANTE: Este Dockerfile usa Python 3.12 que es compatible con Frappe version-15
# Frappe version-16 requiere Python 3.14+ que aún no está disponible en imágenes Docker oficiales
# Por lo tanto, el default es version-15 (configurable mediante FRAPPE_VERSION)

FROM python:3.12-slim

# Variables de entorno
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    NODE_VERSION=20.x

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    libffi-dev \
    libssl-dev \
    libmariadb-dev \
    libpq-dev \
    pkg-config \
    libcups2-dev \
    redis-server \
    redis-tools \
    bash \
    supervisor \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Instalar Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - \
    && apt-get install -y nodejs

# Instalar Yarn (requerido por Frappe)
RUN npm install -g yarn && \
    yarn --version && \
    which yarn

# Instalar wkhtmltopdf para generación de PDFs
# Python 3.12-slim usa Debian Bookworm que puede necesitar libssl1.1 desde repositorio legacy
RUN apt-get update && \
    (apt-get install -y libssl1.1 2>/dev/null || \
     (echo "deb http://deb.debian.org/debian bullseye main" > /etc/apt/sources.list.d/bullseye.list && \
      apt-get update && \
      apt-get install -y -t bullseye libssl1.1 || \
      (wget -q -O /tmp/libssl1.1.deb http://ftp.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1n-0+deb11u7_amd64.deb && \
       dpkg -i /tmp/libssl1.1.deb || apt-get install -yf))) && \
    wget -O /tmp/wkhtmltox.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.bullseye_amd64.deb && \
    apt-get install -y /tmp/wkhtmltox.deb && \
    rm -f /tmp/wkhtmltox.deb /tmp/libssl1.1.deb && \
    rm -f /etc/apt/sources.list.d/bullseye.list 2>/dev/null || true && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Actualizar pip, setuptools y wheel a las últimas versiones
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip --version && \
    python --version

# Instalar frappe-bench
RUN pip install --no-cache-dir frappe-bench

# Crear directorio de trabajo
WORKDIR /home/frappe

# Crear usuario frappe
RUN useradd -m -s /bin/bash frappe \
    && chown -R frappe:frappe /home/frappe

# Configurar crontab para que funcione con el usuario frappe
RUN mkdir -p /var/spool/cron/crontabs \
    && touch /var/spool/cron/crontabs/frappe \
    && chown -R frappe:frappe /var/spool/cron/crontabs \
    && chmod 600 /var/spool/cron/crontabs/frappe

# Configurar Redis para ejecutarse como usuario frappe (solo para desarrollo local)
# En producción (Render), se usará Redis externo
RUN mkdir -p /var/lib/redis /var/log/redis /run/redis \
    && chown -R frappe:frappe /var/lib/redis /var/log/redis /run/redis

# Configurar supervisor y cron mínimamente para que bench init no falle
# Nota: En Render no usamos supervisor/cron, pero bench init los requiere
RUN mkdir -p /var/run/supervisor /var/log/supervisor \
    && touch /var/run/supervisor.sock \
    && chmod 777 /var/run/supervisor /var/log/supervisor /var/run/supervisor.sock \
    && mkdir -p /var/spool/cron/crontabs \
    && chmod 755 /var/spool/cron/crontabs

# Verificar que redis-server esté instalado y accesible
RUN which redis-server || (echo "redis-server no encontrado en PATH" && find /usr -name redis-server 2>/dev/null) && \
    redis-server --version || echo "Advertencia: No se pudo verificar versión de Redis"

# Asegurar que /usr/sbin y /usr/local/bin estén en el PATH
# /usr/local/bin contiene yarn y otros binarios instalados globalmente con npm
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

# Cambiar a usuario frappe
USER frappe

# Script de inicio que configura y ejecuta la aplicación
COPY --chown=frappe:frappe entrypoint.sh /home/frappe/entrypoint.sh
COPY --chown=frappe:frappe entrypoint-simple.sh /home/frappe/entrypoint-simple.sh
COPY --chown=frappe:frappe entrypoint-optimized.sh /home/frappe/entrypoint-optimized.sh
COPY --chown=frappe:frappe entrypoint-prod.sh /home/frappe/entrypoint-prod.sh
COPY --chown=frappe:frappe entrypoint-render.sh /home/frappe/entrypoint-render.sh
COPY --chown=frappe:frappe entrypoint-final.sh /home/frappe/entrypoint-final.sh
COPY --chown=frappe:frappe entrypoint-optimized-v2.sh /home/frappe/entrypoint-optimized-v2.sh
COPY --chown=frappe:frappe entrypoint-simple-final.sh /home/frappe/entrypoint-simple-final.sh
# Convertir CRLF a LF (evita "no such file or directory" en Linux si el archivo tiene finales de línea Windows)
RUN sed -i 's/\r$//' /home/frappe/entrypoint.sh
RUN sed -i 's/\r$//' /home/frappe/entrypoint-simple.sh
RUN sed -i 's/\r$//' /home/frappe/entrypoint-optimized.sh
RUN sed -i 's/\r$//' /home/frappe/entrypoint-prod.sh
RUN sed -i 's/\r$//' /home/frappe/entrypoint-render.sh
RUN sed -i 's/\r$//' /home/frappe/entrypoint-final.sh
RUN sed -i 's/\r$//' /home/frappe/entrypoint-optimized-v2.sh
RUN chmod +x /home/frappe/entrypoint.sh
RUN chmod +x /home/frappe/entrypoint-simple.sh
RUN chmod +x /home/frappe/entrypoint-optimized.sh
RUN chmod +x /home/frappe/entrypoint-prod.sh
RUN chmod +x /home/frappe/entrypoint-render.sh
RUN chmod +x /home/frappe/entrypoint-final.sh
RUN chmod +x /home/frappe/entrypoint-optimized-v2.sh
RUN sed -i 's/\r$//' /home/frappe/entrypoint-simple-final.sh
RUN chmod +x /home/frappe/entrypoint-simple-final.sh

# Exponer puerto
# Nota: Render asigna el puerto dinámicamente mediante la variable PORT (default: 10000)
# El EXPOSE aquí es solo documentación; Render usa PORT para el binding real
EXPOSE 10000

# Comando de inicio
ENTRYPOINT ["/home/frappe/entrypoint.sh"]
