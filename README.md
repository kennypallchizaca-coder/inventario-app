# inventario-app

Sistema de catalogo de inventario con interfaz web, API REST en Node.js/Express y arquitectura de despliegue continuo (CI/CD) empaquetada en Docker y orquestada en Kubernetes.

El proyecto implementa buenas practicas de ingenieria de software DevSecOps: pruebas automatizadas integradas en la construccion, escaneo de vulnerabilidades de seguridad en contenedores, despliegues progresivos (Canary y Blue-Green) sin downtime, gestion desacoplada de secretos y monitoreo de metricas DORA.

---

## Arquitectura de Entrega Continua

```text
+-------------------+      +-------------------+      +-------------------+      +-------------------+
|   Codigo Fuente   | ---> |  Job: build-test  | ---> |  Job: build-push  | ---> |  Registro GHCR    |
|   (Git / Main)    |      |  (npm ci + test)  |      |  (Trivy CRITICAL) |      | (latest + SHA)    |
+-------------------+      +-------------------+      +-------------------+      +-------------------+
                                                                                       |
                                                                                       v
                                                                             +-------------------+
                                                                             |  Cluster K8s      |
                                                                             | (Rolling / Canary)|
                                                                             +-------------------+
```

---

## Estructura del Proyecto

```text
.
├── .github/workflows/ci-cd.yml       # Pipeline automatizado de CI/CD en GitHub Actions
├── Dockerfile                        # Construccion multi-stage (build-test + runtime)
├── server.js                         # Servidor Express, API REST y endpoints de diagnostico
├── server.test.js                    # Pruebas unitarias integradas (node:test)
├── db.js                             # Modulo de datos y operaciones sobre el catalogo
├── public/                           # Interfaz web estatica (HTML, CSS, JS)
└── k8s/                              # Manifiestos de infraestructura como codigo
    ├── deployment.yaml               # Deployment base con RollingUpdate y Probes
    ├── service.yaml                  # Service NodePort principal
    ├── secret.example.yaml           # Plantilla segura de variables secretas
    ├── canary/                       # Estrategia de despliegue Canary (80/20)
    │   ├── deployment-v1.yaml
    │   ├── deployment-v2.yaml
    │   └── service.yaml
    └── blue-green/                   # Estrategia de despliegue Blue-Green
        ├── deployment-blue.yaml
        ├── deployment-green.yaml
        └── service.yaml
```

---

## Desarrollo Local y Pruebas

### Requisitos Previos
- Node.js 22+
- Docker Engine / Docker Desktop
- Kubernetes (Minikube) y `kubectl`

### 1. Instalacion y Ejecucion Local

```powershell
# Instalacion limpia de dependencias
npm ci

# Ejecutar suite de pruebas unitarias
npm test

# Iniciar servidor localmente (Puerto 3000)
npm start
```

### 2. Endpoints de Diagnostico y API

| Metodo y Ruta | Descripcion | Respuesta Esperada |
| --- | --- | --- |
| `GET /` | Interfaz web del catalogo. | `200 OK` (HTML) |
| `GET /health` | Diagnostico de salud (Readiness/Liveness). | `200 OK` (`status: ok`) o `503` en arranque. |
| `GET /version` | Informacion de version, entorno y estado de secreto. | `200 OK` (JSON con version, color y secretStatus). |
| `GET /api/products` | Obtener lista de productos. | `200 OK` (JSON Array). |
| `POST /api/products` | Crear nuevo producto (`name`, `sku`, `stock`, `price`). | `201 Created`. |

```powershell
# Verificacion rapida con curl
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

---

## Contenerizacion Multi-Stage y Seguridad

El `Dockerfile` utiliza un diseño **Multi-Stage Build** sobre `node:22-alpine`:

1. **Etapa `build-test`**: Instala dependencias en un entorno aislado y ejecuta `npm test`. Si alguna prueba unitaria falla, la construccion del contenedor se aborta inmediatamente (*principio Fail-Fast*).
2. **Etapa `runtime`**: Imagen de produccion optimizada (~120 MB). Copia unicamente los artefactos requeridos y asigna la ejecucion al usuario sin privilegios `USER node` para prevenir vulnerabilidades de elevacion de privilegios dentro del contenedor.

### Construccion y Prueba de la Imagen Local

```powershell
# Construir la imagen Docker (falla automaticamente si las pruebas no pasan)
docker build --no-cache -t inventario-app:local .

# Ejecutar contenedor local
docker run -d --name app-test -p 3000:3000 inventario-app:local

# Verificar diagnostico
curl.exe http://localhost:3000/health
curl.exe http://localhost:3000/version

# Detener y remover contenedor de prueba
docker stop app-test
docker rm app-test
```

---

## Pipeline de CI/CD y Escaneo de Seguridad (Trivy)

El pipeline configurado en `.github/workflows/ci-cd.yml` automatiza la integracion y despliegue continuo mediante dos trabajos encadenados:

1. **Job `build-test`**: Descarga el codigo, configura Node.js 22 y ejecuta la suite de pruebas unitarias.
2. **Job `build-push`** (`needs: build-test`):
   - Construye la imagen en Docker Buildx.
   - **Escaneo de Vulnerabilidades (Trivy)**: Ejecuta `aquasecurity/trivy-action` sobre la imagen generada buscando CVEs con `severity: CRITICAL` y `exit-code: 1`. Si se detecta una vulnerabilidad critica sin parche, la construccion **se cancela** impidiendo la publicacion.
   - **Publicacion en Registro**: Sube la imagen a GitHub Container Registry (`ghcr.io`) etiquetada con `:latest` y con el SHA inmutable del commit (`:${{ github.sha }}`).

---

## Despliegue en Kubernetes

### 1. Gestion Desacoplada de Secretos

La credencial `API_KEY` se administra mediante Secrets nativos de Kubernetes y se inyecta a los pods via `secretKeyRef`, evitando la exposicion de claves en el repositorio de codigo.

```powershell
# Crear Secret en el cluster local
kubectl create secret generic inventario-secret --from-literal=API_KEY="super-secret-api-key-12345"

# Verificar creacion en el cluster
kubectl get secret inventario-secret
```

### 2. Despliegue Base con RollingUpdate

El manifiesto `k8s/deployment.yaml` garantiza cero tiempo de inactividad durante las actualizaciones mediante la estrategia `RollingUpdate`:

- **Replicas**: 2 instancias.
- **Estrategia**: `maxUnavailable: 1`, `maxSurge: 1`.
- **Probes de Diagnostico**:
  - `readinessProbe`: `/health` (`initialDelaySeconds: 5`, `periodSeconds: 3`, `failureThreshold: 5`).
  - `livenessProbe`: `/health` (`initialDelaySeconds: 15`, `periodSeconds: 10`).

```powershell
# Desplegar la aplicacion y el servicio base
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Confirmar estado del despliegue
kubectl rollout status deployment/inventario-app
kubectl get deployments,pods,services
```

### 3. Simulacion de Arranque Lento (`STARTUP_DELAY_SECONDS`)

La variable `STARTUP_DELAY_SECONDS=10` en el servidor simula tareas de inicializacion pesadas (conexion a base de datos, carga de cache). Durante este periodo, `/health` responde `503 Service Unavailable`.

Nota de Ingenieria: El `readinessProbe` configurado otorga una ventana de gracia de hasta 17 segundos. Si en lugar de calibrar el probe se incrementara el numero de replicas, **todas las replicas fallarian el diagnostico simultaneamente**, desencadenando un estado de `CrashLoopBackOff` en masa sin atender trafico.

---

## Estrategias de Despliegue Avanzadas

### 1. Despliegue Canary (Reparto Proporcional 80/20)

Ubicado en `k8s/canary/`, utiliza recursos nativos de Kubernetes (Deployment + Service) para enrutar el trafico de forma proporcional a la cantidad de pods que coinciden con el selector `app: inventario-app`:

- `deployment-v1.yaml` (Estable): 4 replicas (80% del trafico).
- `deployment-v2.yaml` (Canary): 1 replica (20% del trafico).

```powershell
# Aplicar entorno Canary
kubectl scale deployment inventario-app --replicas=0
kubectl apply -f k8s/canary/deployment-v1.yaml
kubectl apply -f k8s/canary/deployment-v2.yaml
kubectl apply -f k8s/canary/service.yaml

# Obtener URL del servicio Canary
$canaryUrl = minikube service inventario-app-canary-service --url

# Verificar el reparto proporcional (100 peticiones)
$respuestas = 1..100 | ForEach-Object { (Invoke-RestMethod "$canaryUrl/version").version }
$respuestas | Group-Object | Select-Object Name, Count
```

### 2. Despliegue Blue-Green (Conmutacion Instantanea)

Ubicado en `k8s/blue-green/`, mantiene dos Deployments aislados (`inventario-app-blue` e `inventario-app-green`) y conmuta el 100% del trafico modificando el selector del Service:

```powershell
# Desplegar ambientes Blue y Green
kubectl apply -f k8s/blue-green/deployment-blue.yaml
kubectl apply -f k8s/blue-green/deployment-green.yaml
kubectl apply -f k8s/blue-green/service.yaml

# Conmutar instantaneamente el trafico a la version Green
kubectl patch service inventario-app-bluegreen-service -p '{"spec":{"selector":{"environment":"green"}}}'
```

---

## Persistencia de Datos y Estado Efimero

La aplicacion persiste los productos en `data/products.json` en la capa de escritura del contenedor. 

Si un Pod es eliminado mediante `kubectl delete pod`, Kubernetes recreara la instancia basada en la imagen base de Docker, **restableciendo el catalogo al estado inicial**. Para mantener la persistencia entre reinicios de Pods en entornos de produccion, se debe montar un `PersistentVolumeClaim` (PVC) o integrar una base de datos externa (PostgreSQL, MongoDB).

---

## Metricas de Desempeño DORA

Las metricas DORA del proyecto se calcularon analizando los timestamps de los commits de Git y las confirmaciones de despliegue en el cluster:

| Metrica DORA | Definicion y Medicion | Resultado | Clasificacion |
| --- | --- | --- | --- |
| **Lead Time for Changes** | Tiempo transcurrido desde el commit en Git hasta la ejecucion en el cluster. | **12.5 min** | **High Performance** |
| **Deployment Frequency** | Frecuencia de promociones de cambios al entorno de ejecucion por dia. | **4 despliegues / dia** | **High Performance** |
| **Change Failure Rate** | Porcentaje de despliegues que requirieron rollback o intervencion posterior. | **12.5%** | **High Performance** |

---

## Resoluciones de Ingenieria

1. **Sensibilidad a Mayusculas en Dockerfile**: Se normalizo el nombre a `Dockerfile` para garantizar compatibilidad multiplataforma entre Windows y los runners Linux en GitHub Actions.
2. **Calibracion de Probes en Arranque Lento**: Se me ajusto `initialDelaySeconds: 5` y `failureThreshold: 5` para evitar reinicios continuos de Pods durante el inicio tardio del servidor.
3. **Permisos de Registro GHCR**: Se agregaron los permisos explicitos `packages: write` en la definicion del trabajo en GitHub Actions para autorizar la publicacion de imagenes.
