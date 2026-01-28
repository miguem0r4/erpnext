# ERPNext Docker Setup

Configuración de ERPNext para despliegue en Render.com y desarrollo local.

## ¿Qué es frappe-bench?

**frappe-bench** es la herramienta de línea de comandos oficial de Frappe Framework para gestionar instalaciones de Frappe/ERPNext. Un "bench" es un directorio que contiene:

- **Múltiples aplicaciones** (Frappe Framework, ERPNext, y apps personalizadas)
- **Múltiples sitios** (instancias separadas de ERPNext, cada una con su propia base de datos)
- **Configuración compartida** (Redis, configuración de workers, etc.)
- **Scripts de gestión** (migraciones, backups, actualizaciones)

Cuando ejecutas `bench init`, se crea una estructura de directorios como:
```
frappe-bench/
├── apps/          # Aplicaciones (frappe, erpnext, etc.)
├── sites/         # Sitios (cada sitio es una instancia)
├── env/           # Entorno virtual de Python
└── config/        # Configuración del bench
```

El comando `bench init --frappe-branch version-16` descarga Frappe Framework desde GitHub usando la rama especificada.

## Cambios Realizados

### Problemas Solucionados

1. **Redis no encontrado**: Se agregó `redis-server` al Dockerfile
2. **Puerto no detectado**: El servidor ahora escucha en `0.0.0.0:${PORT}` para Render
3. **Despliegue local**: Se agregó soporte para Redis local cuando no hay `REDIS_URL`
4. **Rama inválida version-17**: Cambiado a `version-16` (versión estable más reciente). Ahora configurable mediante `FRAPPE_VERSION`

## Despliegue en Render.com

### Variables de Entorno Requeridas

Configura estas variables de entorno en Render:

```
DB_HOST=<tu-host-de-base-de-datos>
DB_PORT=3306
DB_NAME=erpnext
DB_USER=<tu-usuario>
DB_PASSWORD=<tu-contraseña>
REDIS_URL=redis://<host-redis>:6379
SITE_NAME=erpnext
ADMIN_PASSWORD=<contraseña-admin>
FRAPPE_VERSION=version-16  # Opcional: version-14, version-15, version-16, develop
```

**Notas**:
- Render proporciona automáticamente la variable `PORT`, no es necesario configurarla
- `FRAPPE_VERSION` por defecto es `version-16` (versión estable más reciente)
- Versiones disponibles: `version-14`, `version-15`, `version-16`, `develop`

### Build Command (Render)

```bash
docker build -t erpnext .
```

### Start Command (Render)

El entrypoint se ejecuta automáticamente. Asegúrate de que el Dockerfile esté configurado correctamente.

## Despliegue Local

### Opción 1: Docker Compose (Recomendado)

1. Edita `docker-compose.yml` y ajusta las variables de entorno según tu configuración
2. Ejecuta:

```bash
docker-compose up -d
```

3. Accede a la aplicación en `http://localhost:8000`

### Opción 2: Docker Directo

1. Construye la imagen:

```bash
docker build -t erpnext .
```

2. Ejecuta el contenedor:

```bash
docker run -d \
  -p 8000:8000 \
  -e DB_HOST=localhost \
  -e DB_PORT=3306 \
  -e DB_NAME=erpnext \
  -e DB_USER=root \
  -e DB_PASSWORD=tu_password \
  -e SITE_NAME=erpnext \
  -e ADMIN_PASSWORD=admin \
  --name erpnext \
  erpnext
```

**Nota**: Para desarrollo local sin `REDIS_URL`, el contenedor iniciará Redis automáticamente.

## Estructura de Archivos

- `Dockerfile`: Imagen Docker con todas las dependencias
- `entrypoint.sh`: Script de inicio que configura y ejecuta ERPNext
- `docker-compose.yml`: Configuración para desarrollo local con MariaDB y Redis

## Solución de Problemas

### Redis no encontrado

Si ves el error `redis-server: not found`:
- Verifica que `redis-server` esté instalado en el Dockerfile
- El PATH incluye `/usr/sbin` y `/usr/bin`
- En Render, proporciona `REDIS_URL` con un servicio Redis externo

### Puerto no detectado

- El servidor debe escuchar en `0.0.0.0` (todas las interfaces)
- Render proporciona `PORT` automáticamente
- Verifica que el comando use `--host 0.0.0.0`

### Base de datos no conecta

- Verifica que las variables de entorno de base de datos estén correctas
- Asegúrate de que la base de datos esté accesible desde el contenedor
- En Render, usa el host interno de la base de datos

### Error: Invalid branch or tag: version-17

Este error ocurre cuando se intenta usar una rama que no existe. Las ramas válidas son:
- `version-14` (EOL: 31 enero 2026)
- `version-15` (EOL: fin de 2027)
- `version-16` (EOL: fin de 2029) - **Recomendada**
- `develop` (versión en desarrollo, puede ser inestable)

Configura `FRAPPE_VERSION=version-16` (o la versión que desees usar).

## Modo Worker

Para ejecutar workers en lugar del servidor web, configura:

```
WORKER_MODE=1
```

Esto es útil para ejecutar workers en contenedores separados.
