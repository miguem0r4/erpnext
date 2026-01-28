# Dockerfile para ERPNext en Render.com
# Basado en Frappe Framework y optimizado para producción

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
    redis-tools \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Instalar Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - \
    && apt-get install -y nodejs

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

# Instalar frappe-bench
RUN pip install --no-cache-dir frappe-bench

# Crear directorio de trabajo
WORKDIR /home/frappe

# Crear usuario frappe
RUN useradd -m -s /bin/bash frappe \
    && chown -R frappe:frappe /home/frappe

# Cambiar a usuario frappe
USER frappe

# Script de inicio que configura y ejecuta la aplicación
COPY --chown=frappe:frappe entrypoint.sh /home/frappe/entrypoint.sh
RUN chmod +x /home/frappe/entrypoint.sh

# Exponer puerto (Render asignará el puerto dinámicamente)
EXPOSE 8000

# Comando de inicio
ENTRYPOINT ["/home/frappe/entrypoint.sh"]
