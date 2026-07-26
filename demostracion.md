# Guion de demostración - inventario-app

Documento de apoyo para reproducir la práctica y registrar evidencias. Ejecutar cada bloque desde `C:\Users\kenny\OneDrive\Documents\inventario-app`. Las capturas deben mostrar el comando completo, el prompt de PowerShell y toda la salida relevante; no se deben recortar resultados ni incluir valores reales de secretos.

## 1. Comprobación previa

```powershell
node --version
npm --version
docker --version
kubectl version --client
minikube status
git status --short
```

El estado de Git debe estar limpio antes de la captura final. No aplicar ningún `secret.yaml` desde el repositorio: el archivo está ignorado intencionalmente.

## 2. Pruebas de la aplicación local

```powershell
npm ci
npm test
npm start
```

En otra ventana PowerShell:

```powershell
curl.exe -i http://localhost:3000/
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

Detener el servidor local con `Ctrl+C` cuando se terminen las consultas. La evidencia de las rutas debe dejar visible `/`, `/health`, `/version` y `/api/products`.

## 3. Docker multi-stage

```powershell
docker build -t inventario-app:local .
docker run -d --name inventario-app-local -p 3000:3000 inventario-app:local
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
docker logs inventario-app-local
docker stop inventario-app-local
docker rm inventario-app-local
```

Guardar una captura de la salida completa de `docker build` en `entregables/evidencias/01-docker-local/01-build-exitoso.png`. Deben verse las etapas `build-test`, la ejecución de `npm test`, la etapa `runtime` y el etiquetado final. Guardar las consultas HTTP en `02-curl-rutas.png`.

## 4. Pipeline de GitHub Actions y GHCR

1. Hacer un commit y un push a `main` solo cuando los cambios estén revisados.
2. Abrir el repositorio en GitHub, pestaña **Actions**, y abrir la ejecución más reciente.
3. Verificar que `build-test` finalice antes de `build-push`.
4. Abrir el paso **Escaneo de seguridad de la imagen con Trivy**. Debe ejecutarse antes de **Publicar imagen en GHCR** y fallar si encuentra severidad `CRITICAL`.
5. Abrir **Packages** o GHCR y verificar las etiquetas `latest` y el SHA del commit.

Guardar las capturas actuales como:

```text
entregables/evidencias/02-github-actions/01-pipeline-verde.png
entregables/evidencias/02-github-actions/02-ghcr-imagen.png
entregables/evidencias/05-componentes-adicionales/trivy-scan.png
```

No usar como evidencia final una captura que muestre `trivy-action@master`, Node 24 o una configuración distinta de `.github/workflows/ci-cd.yml`.

## 5. Secret, RollingUpdate y servicio base

Crear el Secret directamente en Minikube; sustituir el marcador por una clave de prueba que no se publique:

```powershell
kubectl create secret generic inventario-app-secret --from-literal=API_KEY="REEMPLAZAR_POR_VALOR_SEGURO"
kubectl get secret inventario-app-secret
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/inventario-app
kubectl get deployment inventario-app
kubectl get pods -l app=inventario-app
```

Verificación del servicio:

```powershell
$url = minikube service inventario-app-service --url
curl.exe -i "$url/health"
curl.exe -i "$url/version"
curl.exe -i "$url/api/products"
```

Guardar `kubectl rollout status` como `entregables/evidencias/03-minikube-rollout/01-kubectl-rollout-status.png` y las rutas como `02-curl-servicio.png`.

Para demostrar que el Secret se inyecta sin exponerlo:

```powershell
$pod = kubectl get pods -l app=inventario-app,track=base -o jsonpath='{.items[0].metadata.name}'
kubectl describe pod $pod
curl.exe "$url/version"
```

La salida de `describe` debe mostrar `API_KEY` proveniente de `inventario-app-secret`; el endpoint `/version` solo debe informar que el secreto está configurado. Guardar la evidencia en `entregables/evidencias/05-componentes-adicionales/secret-env.png`.

## 6. Readiness y arranque lento

El Deployment define `STARTUP_DELAY_SECONDS=10`, una `startupProbe` y probes de readiness/liveness. Al recrear un Pod, observar la transición sin enviarlo al Service prematuramente:

```powershell
kubectl rollout restart deployment/inventario-app
kubectl get pods -l app=inventario-app,track=base -w
kubectl rollout status deployment/inventario-app
```

Guardar la transición y el rollout aprobado en `entregables/evidencias/05-componentes-adicionales/readiness-tolerado.png`.

## 7. Canary: reparto aproximado 80/20

No ejecutar el Deployment base y los Deployments Canary para la misma muestra de tráfico. El selector base utiliza `track: base`, pero se escala a cero para que la demostración quede inequívoca.

1. Editar `k8s/canary/deployment-canary.yaml` y sustituir `<REEMPLAZAR_CON_SHA_PUBLICADO>` por el SHA que aparece en GHCR tras un pipeline exitoso.
2. Aplicar los manifiestos actuales:

```powershell
kubectl scale deployment inventario-app --replicas=0
kubectl apply -f k8s/canary/deployment-stable.yaml
kubectl apply -f k8s/canary/deployment-canary.yaml
kubectl apply -f k8s/canary/service.yaml
kubectl rollout status deployment/inventario-app-v1
kubectl rollout status deployment/inventario-app-v2
kubectl get pods -l app=inventario-app --show-labels
```

3. Generar una muestra de 100 solicitudes:

```powershell
$canaryUrl = minikube service inventario-app-canary-service --url
1..100 | ForEach-Object { (Invoke-RestMethod "$canaryUrl/version").release } |
  Group-Object | Select-Object Name, Count
```

El resultado esperado es cercano a cuatro respuestas `stable` por cada respuesta `canary` si `/version` expone esa etiqueta; en la evidencia histórica se observaron 81 respuestas estables y 19 canary. El reparto no es exacto por cada petición. Guardar Pods y etiquetas en `entregables/evidencias/04-estrategia-despliegue/pods-corriendo.png` y la muestra completa en `reparto-trafico.png`.

Rollback Canary si se observa una falla:

```powershell
kubectl scale deployment inventario-app-v2 --replicas=0
kubectl get pods -l app=inventario-app
```

## 8. Persistencia de datos

Con el servicio base activo nuevamente, crear un producto, eliminar el Pod y comprobar la pérdida del dato:

```powershell
kubectl scale deployment inventario-app-v1 --replicas=0
kubectl scale deployment inventario-app-v2 --replicas=0
kubectl scale deployment inventario-app --replicas=2
kubectl rollout status deployment/inventario-app
$url = minikube service inventario-app-service --url
curl.exe -X POST "$url/api/products" -H "Content-Type: application/json" -d '{"name":"Producto temporal","sku":"TMP-001","stock":1,"price":9.99}'
curl.exe "$url/api/products"
$pod = kubectl get pods -l app=inventario-app,track=base -o jsonpath='{.items[0].metadata.name}'
kubectl delete pod $pod
kubectl rollout status deployment/inventario-app
curl.exe "$url/api/products"
```

Guardar toda la secuencia en `entregables/evidencias/06-persistencia-datos/producto-perdido.png`. La pérdida se explica porque `data/products.json` está dentro del filesystem efímero del contenedor; no es un defecto de la práctica.

## 9. Registro de métricas DORA

Registrar el comando, la fecha y la salida de cada promoción en `entregables/evidencias/07-metricas-dora/`. Los cálculos de esta práctica son:

| Métrica | Registro | Cálculo | Resultado |
| --- | --- | --- | --- |
| Lead time for changes | Cambio 1: 23/07/2026 14:15:00 a 14:19:32. Cambio 2: 24/07/2026 09:10:00 a 09:14:15. | (4 min 32 s + 4 min 15 s) / 2 | 4 min 24 s |
| Frecuencia de despliegue | 5 despliegues en 3 días. | 5 / 3 | 1,67 despliegues/día |
| Change failure rate | 1 corrección o rollback de 5 despliegues. | (1 / 5) x 100 | 20 % |

Estas métricas están desarrolladas en `entregables/documentos/reporte_reflexion.pdf`. Para que la evidencia sea auditable, la captura debe asociar los dos commits con el momento de `kubectl set image` o la finalización del rollout.

## 10. Revisión previa a la entrega AVAC

```powershell
npm ci
npm test
git status --short
```

Confirmar manualmente que:

- El workflow mostrado corresponde a la versión actual (`Node 22`, `trivy-action@v0.36.0`).
- El Secret se llama `inventario-app-secret` y nunca muestra su valor.
- Las capturas Canary usan `deployment-stable.yaml`, `deployment-canary.yaml` y `service.yaml` actuales.
- `reporte_reflexion.pdf` contiene tres métricas DORA, justificación Canary, persistencia, bitácora y conclusión.
- Todas las capturas muestran comandos completos y salidas legibles.
