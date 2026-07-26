# inventario-app

Aplicación web de inventario con API REST en Node.js/Express y almacenamiento local JSON. El proyecto documenta una práctica de CI/CD con Docker, GitHub Actions, Kubernetes y Minikube.

## Alcance implementado

| Requisito | Implementación verificable |
| --- | --- |
| Contenedor | `Dockerfile` multi-stage: pruebas en `build-test` y ejecución no privilegiada en `runtime`. |
| Integración continua | `.github/workflows/ci-cd.yml`: `npm ci`, `npm test`, build, Trivy y publicación en GHCR. |
| Despliegue base | `k8s/deployment.yaml`: dos réplicas, `RollingUpdate`, probes y recursos. |
| Estrategia adicional | Canary nativo en `k8s/canary/`: cuatro réplicas estables y una canary, con Service común. |
| Componentes adicionales | Secret de Kubernetes, Trivy y simulación de arranque lento con readiness. |
| Persistencia | Se observa y explica la pérdida de datos al recrear un Pod con almacenamiento local. |

La única estrategia adicional entregada es **Canary**. No se incluyen manifiestos Blue-Green.

## Requisitos

- Node.js 22 o posterior.
- Docker Desktop.
- Minikube y `kubectl` para las pruebas de Kubernetes.

## Ejecución local

```powershell
npm ci
npm test
npm start
```

Con el servidor iniciado, verificar los endpoints:

```powershell
curl.exe -i http://localhost:3000/
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

La suite actual contiene seis pruebas. Durante `STARTUP_DELAY_SECONDS`, `GET /health` responde `503`; después del periodo de inicio responde `200`.

## Docker multi-stage

La etapa `build-test` instala dependencias y detiene la construcción si falla `npm test`. La etapa `runtime` copia solo lo necesario, ejecuta con `USER node` y no incorpora herramientas npm/npx.

```powershell
docker build -t inventario-app:local .
docker run -d --name inventario-app-local -p 3000:3000 inventario-app:local
curl.exe http://localhost:3000/health
curl.exe http://localhost:3000/version
curl.exe http://localhost:3000/api/products
docker stop inventario-app-local
docker rm inventario-app-local
```

## Pipeline CI/CD

El workflow se ejecuta en `push` y `pull_request` a `main`.

1. `build-test` configura Node.js 22 y ejecuta `npm ci` y `npm test`.
2. `build-push` depende de la aprobación anterior; construye la imagen con Buildx.
3. Trivy analiza la imagen y falla ante vulnerabilidades `CRITICAL` (`exit-code: 1`).
4. Solo en `push` o ejecución manual, después de aprobar el análisis, la imagen se publica en GHCR con `latest` y con el SHA inmutable del commit. En un pull request se ejecutan las pruebas sin publicar una imagen.

Antes de entregar, se debe adjuntar una captura de una ejecución reciente en `entregables/evidencias/02-github-actions/` y otra de la imagen publicada. La evidencia existente no sustituye una ejecución actual del workflow.

## Kubernetes: despliegue base

Primero crear el Secret real en el clúster. El repositorio solo contiene la plantilla `k8s/secret.example.yaml`; nunca se versiona `k8s/secret.yaml`.

```powershell
kubectl create secret generic inventario-app-secret --from-literal=API_KEY="REEMPLAZAR_POR_VALOR_SEGURO"
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/inventario-app
kubectl get deployments,pods,services
```

El deployment base utiliza dos réplicas y `RollingUpdate` con `maxUnavailable: 1` y `maxSurge: 1`. El endpoint `/health` alimenta `startupProbe`, `readinessProbe` y `livenessProbe`. El arranque lento de diez segundos se tolera mediante `startupProbe`; un Pod solo entra al balanceo cuando devuelve `200`.

```powershell
$url = minikube service inventario-app-service --url
curl.exe "$url/health"
curl.exe "$url/version"
curl.exe "$url/api/products"
```

## Canary con recursos nativos

La variante Canary está formada por:

- `k8s/canary/deployment-stable.yaml`: cuatro réplicas con `release: stable`.
- `k8s/canary/deployment-canary.yaml`: una réplica con `release: canary`.
- `k8s/canary/service.yaml`: selector común `app: inventario-app`.

Kubernetes distribuye las conexiones entre los endpoints disponibles, por lo que la proporción esperada de cuatro Pods estables y uno canary es aproximadamente 80/20 en una muestra suficientemente grande. No es un control de tráfico exacto por solicitud.

El campo `image` del manifest canary contiene el marcador `<REEMPLAZAR_CON_SHA_PUBLICADO>`. Antes de aplicarlo, reemplazarlo por el SHA real que haya publicado GitHub Actions. Esta medida evita declarar como publicado un digest que no está verificado.

```powershell
# No mantener el deployment base y Canary activos para la misma demostración.
kubectl scale deployment inventario-app --replicas=0
kubectl apply -f k8s/canary/deployment-stable.yaml
# Reemplazar el marcador de la imagen antes de ejecutar la siguiente línea.
kubectl apply -f k8s/canary/deployment-canary.yaml
kubectl apply -f k8s/canary/service.yaml

$canaryUrl = minikube service inventario-app-canary-service --url
1..100 | ForEach-Object { (Invoke-RestMethod "$canaryUrl/version").release } |
  Group-Object | Select-Object Name, Count
```

La evidencia de reparto debe recapturarse después de aplicar exactamente estos tres manifiestos y con el SHA publicado. Así quedará alineada con los archivos entregados.

## Persistencia de datos

`data/products.json` reside en el sistema de archivos del contenedor. Al crear un producto y eliminar el Pod, Kubernetes crea otro Pod a partir de la imagen; el producto creado desaparece porque no hay un volumen persistente. Es un resultado intencional de la práctica, no un defecto corregido en esta entrega.

```powershell
$pod = kubectl get pods -l app=inventario-app -o jsonpath='{.items[0].metadata.name}'
kubectl delete pod $pod
kubectl get pods -l app=inventario-app -w
```

## Métricas DORA y reflexión técnica

La reflexión se entrega en PDF y Word; no existe una versión Markdown del documento. Los datos propios registrados para la práctica son los siguientes:

| Métrica | Datos y cálculo | Resultado | Nivel asociado |
| --- | --- | --- | --- |
| Lead time for changes | Cambio 1: 14:15:00 a 14:19:32 = 4 min 32 s. Cambio 2: 09:10:00 a 09:14:15 = 4 min 15 s. Promedio: (272 s + 255 s) / 2. | 4 min 24 s | Alto/élite: menor a una hora. |
| Frecuencia de despliegue | 5 despliegues en 3 días de trabajo. 5 / 3. | 1,67 despliegues por día | Alto: cadencia diaria o superior. |
| Change failure rate | 1 despliegue con corrección o rollback de 5. (1 / 5) × 100. | 20 % | Medio: se requiere reducir las correcciones posteriores. |

El lead time se mide desde el commit hasta la ejecución de `kubectl set image`. La tasa de fallos señala una oportunidad de reforzar las validaciones previas y de conservar Canary como mecanismo de contención. Las capturas de terminal que relacionan commit, promoción y rollout se almacenan en `entregables/evidencias/07-metricas-dora/`.

La reflexión también documenta la decisión Canary (cuatro réplicas estables y una candidata), la pérdida esperada de `data/products.json` al recrear un Pod y tres problemas reales: vulnerabilidad CRITICAL encontrada por Trivy, indisponibilidad durante el arranque lento y desalineación inicial entre las evidencias Canary y los manifiestos.

## Entregables

- [Informe final en PDF](entregables/documentos/informe.pdf)
- [Reflexión técnica en PDF](entregables/documentos/reporte_reflexion.pdf)
- [Reflexión técnica editable en Word](entregables/documentos/reporte_reflexion.docx)
- [Guion de demostración](demostracion.md)
- `entregables/evidencias/`: capturas de Docker, CI/CD, Kubernetes, Canary, componentes adicionales, persistencia y DORA.

Las capturas deben mostrar el comando completo y su salida, sin recortar información relevante. Los archivos de `entregables/` se mantienen fuera del historial de Git por su tamaño; para la entrega AVAC se comprime esa carpeta una vez que se hayan actualizado las evidencias externas.
