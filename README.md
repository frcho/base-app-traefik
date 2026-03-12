# Base App Traefik & Observability Stack

Este proyecto proporciona una infraestructura base utilizando Traefik v2 como proxy inverso, junto con un stack completo de observabilidad (Prometheus, Grafana, Loki, Tempo) y herramientas de gestión.

## 🚀 Inicio Rápido

### Requisitos Previos
1. Tener Docker y Docker Compose (V2) instalados.
2. Crear la red externa para la comunicación entre contenedores:
   ```bash
   docker network create app
   ```
3. Configurar el archivo `.env` basándose en `env.dist`.

### Gestión con Scripts
El proyecto incluye scripts para facilitar la gestión:
* **Iniciar:** `./build-run.sh` (Levanta el stack configurado en el `.env`).
* **Detener:** `./build-stop.sh` (Apaga todos los contenedores).

---

## 🌍 Gestión de Entornos (Dev vs Prod)

El proyecto utiliza una estructura de carpetas y variables dinámicas para adaptarse al entorno sin cambiar el `compose.yaml`.

### Variables clave en `.env`:
* **`ENVIRONMENT`**: Define qué carpeta de configuración cargar (`dev` o `prod`).
* **`TRAEFIK_TLS`**: Activa o desactiva SSL (`true`/`false`).
* **`TRAEFIK_ENTRYPOINTS`**: Define el punto de entrada (`http` o `https`).

#### Ejemplo Configuración Desarrollo:
```env
ENVIRONMENT=dev
DOMAIN_NAME=traefik.localhost
TRAEFIK_ENTRYPOINTS=http
TRAEFIK_TLS=false
```

#### Ejemplo Configuración Producción:
```env
ENVIRONMENT=prod
DOMAIN_NAME=tu-dominio.com
TRAEFIK_ENTRYPOINTS=https
TRAEFIK_TLS=true
TRAEFIK_CERT_RESOLVER=leresolver
TRAEFIK_MIDDLEWARES=redirect-to-https@file
```

---

## 🧩 Perfiles de Servicio (Profiles)

El stack es modular utilizando `COMPOSE_PROFILES` en el `.env`:

| Perfil | Servicios Incluidos | Descripción |
| :--- | :--- | :--- |
| *(ninguno)* | Traefik, DockerProxy | Solo el proxy inverso base. |
| `monitoring` | Prometheus, Grafana, Loki, Tempo, Alloy | Stack completo de métricas, logs y trazas. |
| `tools` | Portainer | Interfaz web para gestión de Docker. |
| `mail` | Mailhog | Servidor SMTP local para pruebas de correo. |

---

## 🛡️ Control de Recursos

Todos los servicios tienen límites estrictos en `compose.yaml` (Ej: Prometheus 1GB RAM, Traefik 256MB) para asegurar la estabilidad del servidor.

**Recomendación de Hardware:**
* **Mínimo:** 2 vCPUs / 4 GB RAM.
* **Recomendado:** 4 vCPUs / 8 GB RAM (Si activas `monitoring`).

---

## 🛠️ Herramientas Recomendadas

Para monitorear los recursos de los contenedores en tiempo real desde la terminal (similar a `top`), se recomienda instalar `ctop`:

```bash
sudo wget https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-amd64 -O /usr/local/bin/ctop
sudo chmod +x /usr/local/bin/ctop
```

---

## 🔗 Acceso a Servicios

URLs por defecto (usando `traefik.localhost`):
* **Traefik Dashboard:** `http://traefik.localhost:8080`
* **Grafana:** `http://grafana.traefik.localhost`
* **Prometheus:** `http://prometheus.traefik.localhost`
* **Portainer:** `http://portainer.traefik.localhost`
* **Mailhog:** `http://mail.traefik.localhost`

> [!IMPORTANT]
> Si tienes un servidor web (Apache/Nginx) corriendo nativamente, apágalo antes de iniciar para liberar los puertos 80/443.
