# ERPNext Docker Setup

Configuración de ERPNext para despliegue en Render.com y desarrollo local.

## Cambios Realizados

### Problemas Solucionados

1. **Redis no encontrado**: Se agregó `redis-server` al Dockerfile
2. **Puerto no detectado**: El servidor ahora escucha en `0.0.0.0:${PORT}` para Render
3. **Despliegue local**: Se agregó soporte para Redis local cuando no hay `REDIS_URL`

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
```

**Nota**: Render proporciona automáticamente la variable `PORT`, no es necesario configurarla.

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

## Modo Worker

Para ejecutar workers en lugar del servidor web, configura:

```
WORKER_MODE=1
```

Esto es útil para ejecutar workers en contenedores separados.
