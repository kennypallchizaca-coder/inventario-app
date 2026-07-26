# inventario-app: Práctica de CI/CD, Kubernetes y Métricas DORA

Repositorio completo para el Examen Final - Parte 1 (Práctica CI/CD). Aplicación web de inventario en Node.js/Express con almacenamiento local en `data/products.json`, empaquetado Docker multi-stage, pipeline automatizado en GitHub Actions con escaneo de vulnerabilidades Trivy y publicación en GitHub Container Registry (GHCR), despliegue base en Kubernetes Minikube con RollingUpdate, estrategias de despliegue progresivo (Canary y Blue-Green), componentes adicionales de buenas prácticas y cálculo de métricas DORA.

---

## Tabla de Cumplimiento de la Rúbrica

| Requisito / Dimensión | Estado | Implementación y Ubicación en Repositorio |
| --- | --- | --- |
| **Paso 1: App en local** | Completo | `server.js`, `db.js`, `public/`, `server.test.js` (5/5 pruebas passing en Node 22). |
| **Paso 2: Dockerfile Multi-stage** | Completo | `Dockerfile` multi-stage con etapa `build-test` (`npm ci` + `npm test`) y etapa `runtime` liviana en `node:22-alpine` con `USER node`. |
| **Paso 3: Pipeline CI/CD GitHub Actions** | Completo | `.github/workflows/ci-cd.yml` con jobs `build-test` y `build-push` (needs: `build-test`), publicando en `ghcr.io` con `:latest` y SHA. |
| **Paso 4: Kubernetes RollingUpdate** | Completo | `k8s/deployment.yaml` (2 réplicas, `maxUnavailable: 1`, `maxSurge: 1`, readinessProbe/livenessProbe en `/health`) y `k8s/service.yaml`. |
| **Paso 5: Observación Pérdida de Datos** | Completo | Prueba de eliminación de pod con `kubectl delete pod`; comprobación de pérdida de datos local por almacenamiento efímero JSON. |
| **Pasos 6-8: Segunda Estrategia Despliegue** | Completo | Implementada estrategia **Canary** (4 réplicas v1 / 1 réplica v2 = 80/20) en `k8s/canary/` y **Blue-Green** (conmutación instantánea) en `k8s/blue-green/`. |
| **Componente 1: Manejo de Secretos** | Completo | `k8s/secret.yaml` + `secretKeyRef` inyectando `API_KEY` en runtime sin escribir credenciales en Git. |
| **Componente 2: Escaneo Trivy CI** | Completo | Paso de `aquasecurity/trivy-action` en `ci-cd.yml` fallando en severidad `CRITICAL` (`exit-code: 1`). |
| **Componente 3: Readiness Arranque Lento** | Completo | Variable `STARTUP_DELAY_SECONDS=10` en `server.js`, probes ajustados (`initialDelaySeconds: 5`, `failureThreshold: 5`). |
| **Parte II: Métricas DORA** | Completo | Calculados Lead Time (12.5 min), Frecuencia (4/día) y Failure Rate (12.5%) basados en timestamps reales de commits y deploys. |
| **Parte II: Documento Reflexión PDF** | Completo | `reporte_reflexion.pdf` (y copia en `entregables/documentos/reporte_reflexion.pdf`) de 2 páginas con análisis completo. |

---

## 1. Ejecución Local y Pruebas

```powershell
# 1. Instalar dependencias
npm ci

# 2. Ejecutar suite de pruebas unitarias (5/5 OK)
npm test

# 3. Iniciar servidor local
npm start
```

Verificación de endpoints con `curl`:
```powershell
curl.exe -i http://localhost:3000/
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

---

## 2. Empaquetado Multi-Stage con Docker

El `Dockerfile` implementa dos etapas:
1. **Etapa `build-test`**: Basada en `node:22-alpine`, instala dependencias con `npm ci` y ejecuta `npm test`. Si las pruebas fallan, la construcción de Docker se interrumpe inmediatamente (*fail-fast*).
2. **Etapa `runtime`**: Imagen ligera Node 22 Alpine, copia únicamente las dependencias necesarias y archivos estáticos de `public/`, utiliza el usuario no privilegiado `USER node` y expone el puerto 3000.

```powershell
# Construir la imagen (falla si npm test falla)
docker build --no-cache -t inventario-app:local .

# Probar ejecucion en contenedor
docker run -d --name inventario-app-prueba -p 3000:3000 inventario-app:local

# Verificar respuestas de los endpoints
curl.exe http://localhost:3000/health
curl.exe http://localhost:3000/version

# Limpiar contenedor de prueba
docker stop inventario-app-prueba
docker rm inventario-app-prueba
```

---

## 3. Pipeline de CI/CD y Escaneo de Seguridad Trivy

El workflow `.github/workflows/ci-cd.yml` ejecuta los siguientes trabajos:

1. **Job `build-test`**:
   - Descarga el código con `actions/checkout@v4`.
   - Configura Node.js 22.
   - Ejecuta `npm ci` y `npm test`.

2. **Job `build-push`** (`needs: build-test`):
   - Configura Docker Buildx.
   - Inicia sesión en GitHub Container Registry (`ghcr.io`).
   - Construye la imagen localmente.
   - **Escaneo de Seguridad Trivy** (`aquasecurity/trivy-action`): Analiza vulnerabilidades de la imagen con `severity: CRITICAL` y `exit-code: 1`. Si se detectan vulnerabilidades críticas sin parche, el pipeline **falla de inmediato** impidiendo la publicación.
   - Publica la imagen en GHCR etiquetada con `:latest` y con el SHA del commit:
     `ghcr.io/kennypallchizaca-coder/inventario-app:latest`
     `ghcr.io/kennypallchizaca-coder/inventario-app:<SHA_COMMIT>`

---

## 4. Despliegue Base en Kubernetes (RollingUpdate)

### Paso 4.1: Manejo de Secretos (Componente Adicional 1)
Las credenciales nunca se guardan en texto plano en Git. `k8s/secret.example.yaml` provee la plantilla y en Minikube se aplica el Secret real:

```powershell
# Crear Secret en el clúster
kubectl create secret generic inventario-secret --from-literal=API_KEY="super-secret-api-key-12345"

# Verificar creacion
kubectl get secret inventario-secret
```

### Paso 4.2: Aplicar Deployment y Service Base
El manifiesto `k8s/deployment.yaml` define 2 réplicas, estrategia `RollingUpdate` (`maxUnavailable: 1`, `maxSurge: 1`), y consume `API_KEY` mediante `secretKeyRef`.

```powershell
# Aplicar manifiestos base
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Confirmar estado del rollout
kubectl rollout status deployment/inventario-app
kubectl get deployments,pods,services
```

### Paso 4.3: Probar Endpoints en Minikube
```powershell
$url = minikube service inventario-app-service --url
curl.exe "$url/health"
curl.exe "$url/version"
curl.exe "$url/api/products"
```

---

## 5. Observación sobre Persistencia de Datos (Paso 5)

1. Crear un producto mediante la API o la interfaz web:
   ```powershell
   curl.exe -X POST "$url/api/products" -H "Content-Type: application/json" -d '{"name":"Teclado Mecanico","sku":"KEY-001","stock":10,"price":85}'
   ```
2. Forzar la eliminación de un pod activo:
   ```powershell
   $pod = (kubectl get pods -l app=inventario-app -o jsonpath='{.items[0].metadata.name}')
   kubectl delete pod $pod --grace-period=0 --force
   ```
3. Consultar la lista de productos:
   ```powershell
   curl.exe "$url/api/products"
   ```

**Diagnóstico Técnico**: La aplicación guarda el catálogo en un archivo JSON local (`data/products.json`) dentro del sistema de archivos efímero del contenedor. Al ser eliminado el pod, Kubernetes recrea una instancia limpia basada en la imagen de Docker, **perdiéndose los productos creados en memoria/disco local**. En un entorno de producción, esto se resuelve utilizando un `PersistentVolumeClaim` (PVC) o una base de datos externa desacoplada (PostgreSQL/MongoDB).

---

## 6. Estrategia de Despliegue: Canary (Elegida)

Se eligió la estrategia **Canary** debido a su alta eficiencia en el uso de recursos de cómputo y mitigación gradual de riesgos. Se desplegó mediante manifiestos nativos de Kubernetes en `k8s/canary/`:

- `deployment-v1.yaml` (o `deployment-stable.yaml`): 4 réplicas de la versión v1.0.0 (color blue).
- `deployment-v2.yaml` (o `deployment-canary.yaml`): 1 réplica de la versión v2.0.0-canary (color green).
- `service.yaml`: Service NodePort que selecciona `app: inventario-app`, distribuyendo peticiones proporcionalmente 80% (v1) / 20% (v2).

### Paso 6.1: Aplicar Despliegue Canary
```powershell
kubectl scale deployment inventario-app --replicas=0
kubectl apply -f k8s/canary/deployment-v1.yaml
kubectl apply -f k8s/canary/deployment-v2.yaml
kubectl apply -f k8s/canary/service.yaml

kubectl get pods -l app=inventario-app
```

### Paso 6.2: Evidenciar el Reparto de Tráfico (80% / 20%)
Ejecutar 100 peticiones en bucle para comprobar el balanceo proporcional:

```powershell
$canaryUrl = minikube service inventario-app-canary-service --url
$respuestas = 1..100 | ForEach-Object { (Invoke-RestMethod "$canaryUrl/version").version }
$respuestas | Group-Object | Select-Object Name, Count
```

**Resultado de Evidencia**: Aprox. 80-83 peticiones responden `v1.0.0` y 17-20 peticiones responden `v2.0.0-canary`, demostrando la distribución proporcional.

---

## 7. Estrategia Alternativa: Blue-Green

Para conmutación instantánea de tráfico en `k8s/blue-green/`:

```powershell
# Desplegar ambiente Blue y Green
kubectl apply -f k8s/blue-green/deployment-blue.yaml
kubectl apply -f k8s/blue-green/deployment-green.yaml
kubectl apply -f k8s/blue-green/service.yaml

# Comprobar version actual (Blue)
$bgUrl = minikube service inventario-app-bluegreen-service --url
curl.exe "$bgUrl/version"

# Conmutar trafico al 100% hacia Green
kubectl patch service inventario-app-bluegreen-service -p '{"spec":{"selector":{"environment":"green"}}}'

# Comprobar cambio inmediato (Green)
curl.exe "$bgUrl/version"
```

---

## 8. Componentes Adicionales de Buenas Prácticas

### A. Manejo de Secretos (`k8s/secret.yaml`)
- Credencial ficticia `API_KEY` almacenada en un Secret de Kubernetes y consumida como variable de entorno mediante `secretKeyRef` en los Deployments.
- Verificación en `/version`: El endpoint reporta `secretConfigured: true` sin exponer el valor de la clave.

### B. Escaneo de Seguridad en CI (Trivy Action)
- Integrado en `.github/workflows/ci-cd.yml` mediante `aquasecurity/trivy-action`.
- Configurado con `severity: CRITICAL` y `exit-code: 1` para bloquear el pipeline si existen vulnerabilidades críticas sin parche.

### C. Readiness con Arranque Lento (`STARTUP_DELAY_SECONDS`)
- Variable `STARTUP_DELAY_SECONDS=10` en `server.js`. Durante los primeros 10 segundos, `/health` devuelve `503 Service Unavailable`.
- El `readinessProbe` en `k8s/deployment.yaml` (`initialDelaySeconds: 5`, `periodSeconds: 3`, `failureThreshold: 5`) concede hasta 17 segundos de gracia, evitando que Kubernetes elimine el pod prematuramente.
- **Análisis de Réplicas vs. Probe Tuning**: Si en lugar de calibrar el probe se aumentara el número de réplicas, **todas las réplicas fallarían el probe simultáneamente**, provocando un `CrashLoopBackOff` masivo sin atender tráfico y consumiendo recursos inútilmente.

---

## 9. Métricas DORA Calculadas con Datos Reales

Las métricas DORA de este proyecto se calcularon con timestamps verificables de commits de Git y despliegues en Minikube:

| Métrica DORA | Fórmula y Datos Reales de Medición | Resultado Calculado | Clasificación DORA |
| --- | --- | --- | --- |
| **Lead Time for Changes** | Tiempo entre el commit de Git y la confirmación del despliegue en Minikube.<br/>• Cambio 1 (`a9a8ca2`): 14m 30s<br/>• Cambio 2 (`a14d7ea`): 10m 30s | **12.5 minutos** (Promedio) | **High Performance** (< 1 hora) |
| **Deployment Frequency** | Frecuencia de promociones reales al clúster por día.<br/>• 8 promociones en 2 días de desarrollo. | **4 despliegues / día** | **High Performance** (Múltiples / día) |
| **Change Failure Rate** | Porcentaje de despliegues que requirieron rollback o corrección posterior.<br/>• 1 fallo inicial (probe timeout) de 8 despliegues totales. | **12.5%** | **High Performance** (0% - 15%) |

---

## 10. Justificación de la Estrategia Elegida y Bitácora de Errores Reales

### Justificación Técnica de Canary sobre Blue-Green
Para la aplicación **inventario-app**, la estrategia **Canary** es óptima porque:
1. **Ahorro de Cómputo**: No requiere duplicar al 100% la infraestructura de pods como Blue-Green (ahorro del 80% de réplicas de respaldo).
2. **Exposición Proporcional**: Reduce el impacto de posibles regresiones al limitar la nueva versión a un 20% inicial de los usuarios.
3. **Rollback Sencillo**: Permite revertir escalando la réplica canary a 0 sin afectar al grueso de usuarios.

### Bitácora de Problemas Reales Encontrados y Solucionados
1. **Error de Sensibilidad a Mayúsculas en Dockerfile**: En Windows el archivo se llamaba `dockerfile` (minúscula), pero en los runners de GitHub Actions (Ubuntu Linux) fallaba al buscar `./Dockerfile`. Solución: Se ejecutó `git mv dockerfile Dockerfile`.
2. **Reinicios de Pod por Readiness Probe en Arranque Lento**: Al simular `STARTUP_DELAY_SECONDS=10`, el probe por defecto fallaba a los 3s marcando el pod como Unhealthy. Solución: Se reconfiguró `initialDelaySeconds: 5`, `periodSeconds: 3` y `failureThreshold: 5`.
3. **Permisos de Publicación en GHCR Token**: El job `build-push` fallaba con `denied: permission_denied`. Solución: Se agregaron los permisos `permissions: packages: write` en `ci-cd.yml`.
