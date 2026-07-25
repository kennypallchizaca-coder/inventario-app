# inventario-app — CI/CD, Kubernetes y Pruebas de Despliegue

Este repositorio contiene la solución completa para la práctica de laboratorio de **CI/CD, Estrategias de Despliegue en Kubernetes y Métricas DORA**, desarrollada sobre la aplicación **inventario-app** (interfaz web REST en Node.js/Express con persistencia local en JSON).

---

## 📌 Contenido del Repositorio

- `Dockerfile`: Multi-stage Docker build (etapa `build-test` con `npm test` y etapa final mínima `runtime`).
- `.github/workflows/ci-cd.yml`: Workflow automatizado con `build-test`, escaneo de vulnerabilidades **Trivy** (severidad `CRITICAL`), y publicación en **GHCR** (`ghcr.io`).
- `k8s/`:
  - `secret.yaml`: Configuración de credenciales ficticias (`API_KEY`) mediante Secrets de K8s.
  - `deployment.yaml`: Deployment base con 2 réplicas, estrategia `RollingUpdate`, `readinessProbe` y `livenessProbe` adaptadas a arranque lento.
  - `service.yaml`: Service nativo tipo NodePort.
  - `canary/`: Manifiestos para despliegue Canary (`deployment-v1.yaml` [4 réplicas / 80%], `deployment-v2.yaml` [1 réplica / 20%], `service.yaml`).
  - `blue-green/`: Manifiestos para despliegue Blue-Green (`deployment-blue.yaml`, `deployment-green.yaml`, `service.yaml`).
- `reporte_reflexion.pdf`: Informe de reflexión de 2 páginas con justificación técnica, observaciones de persistencia de datos local y métricas DORA.

---

## 🚀 Guía de Reproducción Paso a Paso

### 1. Ejecución y Pruebas en Local (Sin Docker)

```bash
# Instalar dependencias
npm install

# Ejecutar suite de pruebas unitarias
npm test

# Iniciar servidor localmente
npm start
```

Verificar respuestas con `curl`:
```bash
curl -i http://localhost:3000/
curl -i http://localhost:3000/health
curl -i http://localhost:3000/version
curl -i http://localhost:3000/api/products
```

---

### 2. Empaquetado Multi-Stage con Docker

Construcción y prueba de la imagen local:
```bash
# Construir imagen multi-stage (falla la construccion si npm test falla)
docker build -t inventario-app:local .

# Ejecutar contenedor local
docker run -d -p 3000:3000 --name app-local inventario-app:local

# Verificar endpoints
curl http://localhost:3000/health
curl http://localhost:3000/version

# Detener y eliminar contenedor
docker stop app-local && docker rm app-local
```

---

### 3. Pipeline CI/CD en GitHub Actions (con Escaneo Trivy)

El pipeline configurado en `.github/workflows/ci-cd.yml` ejecuta:
1. **Job `build-test`**: Instala dependencias con `npm ci` y ejecuta `npm test`.
2. **Job `build-push`**:
   - Construye la imagen en Docker Buildx.
   - Ejecuta escaneo de seguridad con **Trivy Action** en busca de vulnerabilidades `CRITICAL`. Si encuentra alguna sin parche, **el build falla automáticamente (fail-fast)**.
   - Publica la imagen en GitHub Container Registry (`ghcr.io/<USUARIO>/inventario-app`) etiquetada con `:latest` y con el SHA del commit.

---

### 4. Despliegue Base en Kubernetes (Minikube / RollingUpdate)

#### Paso 4.1: Crear el Secret y Desplegar la Aplicación
```bash
# 1. Aplicar Secret de K8s (Componente Adicional 1)
kubectl apply -f k8s/secret.yaml

# 2. Desplegar Deployment y Service base
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# 3. Verificar estado del rollout y pods
kubectl rollout status deployment/inventario-app
kubectl get pods -l app=inventario-app
kubectl get svc inventario-app-service
```

#### Paso 4.2: Prueba de Endpoints sobre el Clúster
```bash
# Obtener la URL del servicio en Minikube
minikube service inventario-app-service --url

# Probar endpoints en la URL asignada (ejemplo http://127.0.0.1:XXXXX)
curl http://<MINIKUBE_IP>:<NODE_PORT>/health
curl http://<MINIKUBE_IP>:<NODE_PORT>/version
```

---

### 5. Observación sobre Persistencia de Datos (Parte I - Paso 5)

1. Abrir la interfaz web (`http://<MINIKUBE_IP>:<NODE_PORT>/`) y crear un nuevo producto (ej. `Teclado Mecánico`, SKU: `KEY-001`).
2. Eliminar un pod arbitrario del Deployment:
   ```bash
   kubectl delete pod -l app=inventario-app --field-selector status.phase=Running --grace-period=0 --force
   ```
3. Realizar peticiones consecutivas a `GET /api/products`:
   - **Observación**: Debido a que la base de datos se guarda en un archivo JSON local (`data/products.json`) dentro del sistema de archivos efímero del pod, el pod recreado no contendrá el producto recién creado, o las peticiones alternarán dependiendo de a qué pod sean dirigidas por el Service.
   - **Diagnóstico**: Esta es una consecuencia directa del estado en memoria/disco local en contenedores estateless sin volúmenes persistentes (`PersistentVolumeClaim`) o base de datos externa.

---

### 6. Estrategia de Despliegue: Canary (Elegida)

En la carpeta `k8s/canary/` se encuentran los manifiestos para un reparto de tráfico **80% (v1) / 20% (v2)**.

#### Paso 6.1: Desplegar v1 (4 réplicas) y Canary v2 (1 réplica)
```bash
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/canary/deployment-v1.yaml
kubectl apply -f k8s/canary/deployment-v2.yaml
kubectl apply -f k8s/canary/service.yaml
```

#### Paso 6.2: Demostración del Reparto Proporcional de Tráfico
Ejecutar un bucle de 20 peticiones `curl` al endpoint `/version`:
```bash
for i in {1..20}; do curl -s http://<MINIKUBE_IP>:<NODE_PORT>/version | jq -c '{version, color}'; done
```
**Resultado Esperado**: Aprox. 16 respuestas mostrarán `version: v1.0.0` (blue) y 4 respuestas mostrarán `version: v2.0.0-canary` (green).

---

### 7. Estrategia Alternativa: Blue-Green

En la carpeta `k8s/blue-green/` se encuentran los manifiestos para conmutación instantánea.

#### Despliegue y Conmutación:
```bash
# 1. Desplegar ambiente Blue y Green
kubectl apply -f k8s/blue-green/deployment-blue.yaml
kubectl apply -f k8s/blue-green/deployment-green.yaml
kubectl apply -f k8s/blue-green/service.yaml

# 2. Verificar que responde Blue
curl http://<MINIKUBE_IP>:<NODE_PORT>/version

# 3. Conmutar el selector del Service hacia Green
kubectl patch service inventario-app-bluegreen-service -p '{"spec":{"selector":{"environment":"green"}}}'

# 4. Verificar conmutacion instantanea
curl http://<MINIKUBE_IP>:<NODE_PORT>/version
```

---

### 8. Componentes Adicionales Implementados

#### 🔑 A. Manejo de Secretos (`k8s/secret.yaml`)
- Credencial ficticia `API_KEY` almacenada en un Secret de Kubernetes y consumida como variable de entorno mediante `secretKeyRef` en los Deployments.
- Verificación en `/version`: La clave es leída por la app sin quedar expuesta en el código fuente de Git.

#### 🛡️ B. Escaneo de Seguridad en CI (Trivy Action)
- Paso automatizado en `.github/workflows/ci-cd.yml` usando `aquasecurity/trivy-action`.
- Configurado con `exit-code: 1` y `severity: CRITICAL` para bloquear la publicación de imágenes vulnerables.

#### ⏱️ C. Readiness con Arranque Lento (`STARTUP_DELAY_SECONDS`)
- Variable de entorno `STARTUP_DELAY_SECONDS=10` en `server.js`.
- Durante los primeros 10 segundos, `/health` responde `503 Service Unavailable`.
- El `readinessProbe` en `k8s/deployment.yaml` (`initialDelaySeconds: 5`, `failureThreshold: 5`, `periodSeconds: 3`) espera tolerando este retraso sin reiniciar ni matar al Pod.

---

## 📈 Métricas DORA (Parte II)

| Métrica DORA | Valor Calculado | Clasificación DORA |
|---|---|---|
| **Lead Time for Changes** | ~14 minutos | **High / Medium** |
| **Deployment Frequency** | 4 despliegues / día | **High** |
| **Change Failure Rate** | 12.5% (1 rollback de 8 intentos) | **High** |

*(Consulta los detalles completos de las métricas en el archivo `reporte_reflexion.pdf`).*
