# Entregables - inventario-app

Paquete de entrega para la práctica de CI/CD. Contiene el Dockerfile, el workflow de GitHub Actions, los manifiestos de Kubernetes, el informe y las evidencias. La estrategia adicional seleccionada es únicamente **Canary**.

## Contenido y cumplimiento

| Criterio | Archivo o evidencia |
| --- | --- |
| Docker multi-stage con pruebas | `Dockerfile` |
| Pipeline test - Trivy - GHCR | `.github/workflows/ci-cd.yml` |
| RollingUpdate, dos réplicas y probes | `k8s/deployment.yaml` |
| Service base | `k8s/service.yaml` |
| Secret sin credenciales versionadas | `k8s/secret.example.yaml` |
| Canary 4:1 | `k8s/canary/` |
| Informe técnico | `documentos/informe.pdf` |
| Reflexión de dos páginas con DORA | `documentos/reporte_reflexion.pdf` y `documentos/reporte_reflexion.docx` |

## Ejecución local

Desde la raíz del proyecto original, instalar y probar:

```powershell
npm ci
npm test
npm start
```

Verificación de rutas:

```powershell
curl.exe -i http://localhost:3000/
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

## Construcción Docker

```powershell
docker build -t inventario-app:local .
docker run -d --name inventario-app-local -p 3000:3000 inventario-app:local
curl.exe http://localhost:3000/health
curl.exe http://localhost:3000/version
curl.exe http://localhost:3000/api/products
docker stop inventario-app-local
docker rm inventario-app-local
```

La etapa `build-test` ejecuta la suite de pruebas. La etapa `runtime` usa `USER node` y conserva solo los artefactos de ejecución.

## Pipeline CI/CD

El workflow ejecuta `npm ci` y `npm test`; después construye la imagen, analiza vulnerabilidades CRITICAL con Trivy y publica en GHCR las etiquetas `latest` y el SHA del commit. El paso de publicación depende de la aprobación del análisis.

Recapturar antes de entregar las evidencias de una ejecución actual:

- `evidencias/02-github-actions/01-pipeline-verde.png`
- `evidencias/02-github-actions/02-ghcr-imagen.png`
- `evidencias/05-componentes-adicionales/trivy-scan.png`

## Kubernetes base

Crear el Secret real, sin guardar su valor en ningún archivo versionado:

```powershell
kubectl create secret generic inventario-app-secret --from-literal=API_KEY="REEMPLAZAR_POR_VALOR_SEGURO"
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/inventario-app
$url = minikube service inventario-app-service --url
curl.exe "$url/health"
curl.exe "$url/version"
curl.exe "$url/api/products"
```

El Deployment base usa dos réplicas, `RollingUpdate`, `startupProbe`, `readinessProbe` y `livenessProbe`. Durante los diez segundos simulados de arranque, el Pod no recibe tráfico hasta estar listo.

## Canary nativo

`deployment-stable.yaml` crea cuatro Pods estables y `deployment-canary.yaml` uno candidato. El Service común selecciona `app: inventario-app`, por lo que el reparto esperado es cercano a 80/20 y no una cuota exacta por solicitud.

```powershell
kubectl scale deployment inventario-app --replicas=0
kubectl apply -f k8s/canary/deployment-stable.yaml
# Sustituir <REEMPLAZAR_CON_SHA_PUBLICADO> por el SHA publicado en GHCR.
kubectl apply -f k8s/canary/deployment-canary.yaml
kubectl apply -f k8s/canary/service.yaml
$canaryUrl = minikube service inventario-app-canary-service --url
1..100 | ForEach-Object { (Invoke-RestMethod "$canaryUrl/version").release } |
  Group-Object | Select-Object Name, Count
```

La captura Canary debe obtenerse con estos tres manifiestos, no con los nombres de archivos anteriores.

## Persistencia y métricas DORA

La pérdida de un producto al recrear el Pod es intencional: `data/products.json` pertenece al filesystem efímero del contenedor. Las tres métricas propias y sus cálculos están en `documentos/reporte_reflexion.pdf` y `documentos/reporte_reflexion.docx`: lead time promedio de 4 min 24 s, frecuencia de 1,67 despliegues por día y change failure rate de 20 %. No se incluye una reflexión en Markdown.

## Evidencias y entrega

Las capturas deben mostrar el comando completo y su salida. Mantener las evidencias en `evidencias/` por categoría y comprimir esta carpeta `entregables` solo después de recapturar Pipeline, GHCR, Trivy, Canary y DORA con la configuración actual.
