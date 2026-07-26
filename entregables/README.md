# Paquete de entregables: inventario-app

Este paquete reúne los manifiestos, las evidencias y los documentos de la práctica. La aplicación fuente se encuentra en la raíz del repositorio. No contiene secretos reales.

# inventario-app: práctica final de CI/CD

## Arquitectura

```text
Código -> npm ci + npm test -> Docker build-test -> Trivy -> GHCR
                                                        |
                                                        v
                         Kubernetes/Minikube: Deployment base o Canary
                         /             |                \
                    /health        /version       /api/products
```

La persistencia es deliberadamente local para la observación solicitada en la práctica. No es una base SQLite: cada contenedor escribe en su propio `data/products.json`.

## Requisitos

- Node.js 22.
- Docker Desktop o Docker Engine.
- Minikube y `kubectl`.
- Git y una cuenta con permiso para publicar en GHCR.
- PowerShell para los ejemplos de Windows.

## Ejecución local y pruebas

```powershell
npm ci
npm test
npm start
```

La aplicación expone `http://localhost:3000`. Verifique las rutas:

```powershell
curl.exe -i http://localhost:3000/
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

`/health` devuelve `503` y `status: not-ready` durante `STARTUP_DELAY_SECONDS`; al finalizar el periodo devuelve `200` y `status: ok`. `/version` informa versión, color, hostname y `secretConfigured`; nunca devuelve ni enmascara fragmentos de `API_KEY`.

## Docker multi-stage

La etapa `build-test` de `Dockerfile` usa `node:22-alpine`, instala con `npm ci` y ejecuta `npm test`. Por ello, una prueba fallida detiene la construcción. La etapa `runtime` copia solo dependencias y archivos de ejecución, crea `/app/data`, usa `USER node`, expone el puerto 3000 y ejecuta `server.js`.

```powershell
docker build --no-cache -t inventario-app:local .
docker run -d --name inventario-app-prueba -p 3000:3000 inventario-app:local
curl.exe http://localhost:3000/health
curl.exe http://localhost:3000/version
docker stop inventario-app-prueba
docker rm inventario-app-prueba
```

`.dockerignore` excluye dependencias locales, archivos de depuración, Git y archivos de sistema sin excluir los datos que requiere la construcción.

## Pipeline CI/CD y GHCR

`.github/workflows/ci-cd.yml` se ejecuta en `push` a `main` y mediante `workflow_dispatch`. El job `build-test` ejecuta `npm ci` y `npm test` con Node.js 22. El job `build-push` depende de `build-test`; construye una imagen local, ejecuta Trivy con `exit-code: 1` y severidad `CRITICAL`, y solo después publica.

Las etiquetas configuradas son:

```text
ghcr.io/kennypallchizaca-coder/inventario-app:latest
ghcr.io/kennypallchizaca-coder/inventario-app:${{ github.sha }}
```

El workflow usa `aquasecurity/trivy-action@v0.36.0`, una versión publicada, no la rama mutable `master`. La imagen desplegada como estable usa la etiqueta SHA verificada en la evidencia de GHCR: `a14d7eaf5dbbd322d392af20b5d234a01e68da26`.

## Secret de Kubernetes

`k8s/secret.example.yaml` es solo una plantilla con `REEMPLAZAR_LOCALMENTE`; `k8s/secret.yaml` está ignorado por Git. Cree el Secret real localmente sin imprimir su valor:

```powershell
kubectl create secret generic inventario-app-secret --from-literal=API_KEY=$env:INVENTARIO_API_KEY
```

El Deployment lo consume mediante `secretKeyRef`. Si se prefiere usar un manifiesto local, créelo desde la plantilla como `k8s/secret.yaml`, asigne el valor fuera de Git y ejecute `kubectl apply -f k8s/secret.yaml`.

## Despliegue base: RollingUpdate

El Deployment base tiene dos réplicas, `RollingUpdate`, `maxUnavailable: 1`, `maxSurge: 1`, solicitudes y límites de recursos. Sus Pods se aíslan con `app: inventario-app` y `track: base`. El Service base usa los mismos selectores. `readinessProbe`, `livenessProbe` y `startupProbe` consultan `/health`; la configuración tolera `STARTUP_DELAY_SECONDS=10` sin reinicios durante el arranque.

El selector de un Deployment es inmutable. Para adoptar la etiqueta `track: base` en un clúster que tenía el manifiesto anterior, ejecute explícitamente:

```powershell
kubectl delete deployment inventario-app
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/inventario-app
kubectl get deployments,pods,services
```

## Estrategia Canary nativa

La estrategia usa dos Deployments y un Service de Kubernetes, sin Argo Rollouts:

- `deployment-stable.yaml`: cuatro réplicas con `release: stable` e imagen SHA inmutable comprobada.
- `deployment-canary.yaml`: una réplica con `release: canary`. Su imagen contiene `<REEMPLAZAR_CON_SHA_PUBLICADO>` hasta que exista una etiqueta SHA publicada y verificable en GHCR.
- `service.yaml`: selecciona solamente `app: inventario-app`, como exige la estrategia de reparto nativa.

Antes de aplicar Canary, reemplace el marcador por un SHA realmente publicado. Como el Service Canary selecciona solo `app`, no debe coexistir con las réplicas del Deployment base durante la medición; escale el base a cero o elimínelo para evitar que altere la muestra.

```powershell
# Confirmar y reemplazar el SHA Canary publicado en k8s/canary/deployment-canary.yaml.
kubectl scale deployment inventario-app --replicas=0
kubectl apply -f k8s/canary/deployment-stable.yaml
kubectl apply -f k8s/canary/deployment-canary.yaml
kubectl apply -f k8s/canary/service.yaml
kubectl get pods -l app=inventario-app
$canaryUrl = minikube service inventario-app-canary-service --url
1..100 | ForEach-Object { (Invoke-RestMethod "$canaryUrl/version").version } | Group-Object | Select-Object Name,Count
```

La evidencia disponible registra 81 solicitudes estables y 19 Canary en una muestra de 100. La relación 4:1 aproxima un reparto 80/20, pero Kubernetes Service no garantiza un porcentaje exacto porque distribuye conexiones, no una cuota determinista por petición.

Para revertir, escale Canary a cero y recupere la versión estable:

```powershell
kubectl scale deployment inventario-app-v2 --replicas=0
kubectl scale deployment inventario-app-v1 --replicas=4
```

## Persistencia de datos

Los productos se almacenan en el filesystem del contenedor, en `data/products.json`. Al eliminar y recrear un Pod, los datos creados pueden perderse porque la capa de escritura no es persistente. Aumentar réplicas no resuelve este problema: cada réplica puede conservar una copia diferente e inconsistente. Una solución de producción requeriría un `PersistentVolume`/`PersistentVolumeClaim` o una base de datos externa; no se implementa aquí porque la pérdida de datos es una observación de la práctica.

## Métricas DORA

No hay en el repositorio timestamps verificables del final de los rollouts ni historial de correcciones/rollback suficiente para calcular métricas reales. Por integridad académica, no se publican números estimados.

| Métrica | Fórmula | Estado actual |
| --- | --- | --- |
| Lead time for changes | Hora de Deployment ejecutándose - hora del commit | PENDIENTE DE COMPLETAR CON EVIDENCIA REAL. |
| Frecuencia de despliegue | Promociones reales al Deployment / periodo | PENDIENTE DE COMPLETAR CON EVIDENCIA REAL. |
| Change failure rate | (Despliegues con corrección o rollback / total) x 100 | PENDIENTE DE COMPLETAR CON EVIDENCIA REAL. |

Capture `git log --format='%H | %aI | %s'`, `kubectl rollout history deployment/inventario-app` y eventos/bitácora del clúster. Registre el mismo resultado en este README, el informe y la reflexión.

## Problemas técnicos corregidos

| Problema | Corrección |
| --- | --- |
| El runtime y CI usaban Node.js 24. | Dockerfile y workflow se ajustaron a Node.js 22 Alpine. |
| Trivy usaba una referencia mutable. | Se fijó `aquasecurity/trivy-action@v0.36.0`. |
| `/version` exponía un fragmento de `API_KEY`. | Ahora informa exclusivamente `secretConfigured`. |
| La base no tenía aislamiento `track: base`; Canary usaba `latest`. | Se aislaron los selectores base y se usaron etiquetas SHA/ marcador de SHA para Canary. |
| La documentación mencionaba SQLite y métricas no auditables. | Se corrigió a JSON local y se marcaron los datos DORA pendientes. |

## Evidencias y documentos

Las evidencias reales se conservan en `evidencias/`. Las capturas existentes documentan build Docker, rutas, pipeline, GHCR, rollout, consulta del Service, Pods Canary, reparto 81/19, Secret, readiness y persistencia. Deben recapturarse las que muestran Node 24 o Trivy `@master`, porque ya no representan la configuración corregida. La carpeta `07-metricas-dora` se reserva para timestamps reales.

- [Informe técnico Word](documentos/informe_final_ci_cd_mejorado.docx)
- [Reflexión PDF](documentos/reporte_reflexion.pdf)
- [Fuente editable de reflexión](documentos/reporte_reflexion.md)
- [URL pública del repositorio](ENLACE_GITHUB.txt)

## Validación final

```powershell
npm ci
npm test
docker build --no-cache -t inventario-app:local .
docker run -d --name inventario-app-prueba -p 3000:3000 inventario-app:local
curl.exe http://localhost:3000/health
curl.exe http://localhost:3000/version
docker stop inventario-app-prueba
docker rm inventario-app-prueba

# Secret local, no versionado:
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/inventario-app
kubectl get deployments,pods,services
```
