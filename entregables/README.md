# Inventario App: CI/CD, Kubernetes y métricas DORA

Implementación de una aplicación web de inventario en Node.js/Express para demostrar un flujo de integración y entrega continua. El repositorio incluye pruebas automatizadas, una imagen Docker multi-stage, publicación en GitHub Container Registry, despliegue RollingUpdate, estrategias Canary y Blue-Green, controles de seguridad y evidencia de métricas DORA.

## Alcance y cumplimiento

| Criterio | Implementación | Evidencia verificable |
| --- | --- | --- |
| Integración continua | GitHub Actions instala dependencias con `npm ci` y ejecuta `npm test`. | Workflow `.github/workflows/ci-cd.yml`; ejecución exitosa del workflow #5. |
| Contenerización | `Dockerfile` multi-stage: pruebas en `build-test` y ejecución mínima en `runtime`. | `docker build` ejecuta las pruebas antes de crear la imagen final. |
| Seguridad | Trivy bloquea vulnerabilidades de severidad `CRITICAL`; los secretos no se versionan. | `exit-code: 1`, `secretKeyRef`, `.gitignore` y `k8s/secret.example.yaml`. |
| Despliegue base | Deployment con dos réplicas, RollingUpdate, readiness y liveness probes. | `k8s/deployment.yaml`; rollout exitoso con 2/2 réplicas disponibles. |
| Canary | Dos versiones con proporción 4:1 y Service aislado mediante `rollout: canary`. | 100 solicitudes: v1.0.0=83 y v2.0.0-canary=17. |
| Blue-Green | Manifiestos y conmutación de selector del Service. | `k8s/blue-green/`; cambio inmediato de tráfico entre entornos. |
| Métricas DORA | Lead time, frecuencia de despliegue y change failure rate calculados con timestamps reales. | Sección [Métricas DORA](#métricas-dora) e informes adjuntos. |

## Arquitectura y flujo de entrega

```text
Código fuente
    |
    +--> npm ci + npm test
    |
    +--> Docker multi-stage
    |
    +--> Trivy (CRITICAL bloquea la publicación)
    |
    +--> GHCR: latest + SHA del commit
    |
    +--> Kubernetes
           |- Deployment base: RollingUpdate, 2 réplicas
           |- Canary: v1 (4) + v2 (1)
           `- Blue-Green: selector conmutable del Service
```

## Estructura del repositorio

```text
.
├── .github/workflows/ci-cd.yml       Pipeline de pruebas, escaneo y publicación
├── Dockerfile                        Imagen multi-stage de la aplicación
├── server.js                         API HTTP y endpoints de salud/versión
├── server.test.js                    Pruebas automatizadas con node:test
├── k8s/
│   ├── deployment.yaml               Despliegue base RollingUpdate
│   ├── service.yaml                  Service NodePort base
│   ├── secret.example.yaml           Plantilla segura del Secret
│   ├── canary/                       Manifiestos Canary
│   └── blue-green/                   Manifiestos Blue-Green
├── informe_final_ci_cd.docx          Informe final con capturas y CodeSnaps
└── reporte_reflexion.pdf             Reflexión técnica y métricas DORA
```

## Requisitos

- Node.js 24 o una versión compatible con el proyecto.
- Docker Desktop o Docker Engine.
- Kubernetes local con Minikube y `kubectl`.
- PowerShell para los comandos de Windows descritos en este documento.
- Acceso autenticado a GitHub Container Registry cuando se usen imágenes privadas.

## Ejecución local y pruebas

Instale las dependencias de manera reproducible y ejecute las pruebas antes de iniciar la aplicación:

```powershell
npm ci
npm test
npm start
```

La aplicación escucha en `http://localhost:3000`. Los endpoints de verificación son:

```powershell
curl.exe -i http://localhost:3000/
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

| Endpoint | Respuesta esperada | Propósito |
| --- | --- | --- |
| `GET /health` | `200` cuando la aplicación está lista; `503` durante el arranque lento configurado. | Readiness y liveness probes. |
| `GET /version` | Versión, color, estado del Secret y clave enmascarada. | Trazabilidad del despliegue sin revelar secretos. |
| `GET /api/products` | Lista de productos. | Verificación funcional de la API. |

Resultado observado: la suite automatizada aprobó 5 de 5 pruebas, incluyendo operaciones de productos y validaciones de API.

## Imagen Docker multi-stage

El `Dockerfile` separa la compilación y las pruebas de la imagen de ejecución:

1. La etapa `build-test` ejecuta `npm ci` y `npm test`.
2. La etapa `runtime` contiene solamente lo necesario para ejecutar `server.js` como el usuario no privilegiado `node`.
3. `npm` y `npx` se eliminan de la imagen de ejecución para reducir la superficie de ataque; la aplicación no los requiere en producción.

Construcción y ejecución local:

```powershell
docker build -t inventario-app:local .
docker run -d --name inventario-app-local -p 3000:3000 inventario-app:local

curl.exe http://localhost:3000/health
curl.exe http://localhost:3000/version

docker stop inventario-app-local
docker rm inventario-app-local
```

El comando `docker build` falla si la suite de pruebas falla; por ello no se genera una imagen final a partir de código no validado.

## Pipeline de CI/CD

El workflow [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml) se activa ante cambios en la rama `main` y también puede ejecutarse manualmente. Está compuesto por dos jobs secuenciales:

1. `build-test`: descarga el repositorio, configura Node.js 24, ejecuta `npm ci` y `npm test`.
2. `build-push`: depende de `build-test`; construye una imagen local, ejecuta Trivy y, solo si el análisis es satisfactorio, publica en GitHub Container Registry.

Las imágenes publicadas tienen dos etiquetas:

```text
ghcr.io/kennypallchizaca-coder/inventario-app:latest
ghcr.io/kennypallchizaca-coder/inventario-app:<sha-completo-del-commit>
```

La etiqueta SHA permite asociar una imagen exacta con el código que la produjo. La etiqueta `latest` facilita la referencia de desarrollo; para una promoción controlada se recomienda desplegar una etiqueta SHA inmutable.

### Evidencia de ejecución del pipeline

| Ejecución | Commit | Resultado | Alcance validado |
| --- | --- | --- | --- |
| Workflow #4 | `a14d7ea` | Success | Pruebas, construcción, Trivy y publicación en GHCR. |
| Workflow #5 | `8f276b8` | Success | Ejecución posterior al informe final; confirma que el repositorio continúa integrando correctamente. |

El historial puede revisarse en la pestaña [Actions del repositorio](https://github.com/kennypallchizaca-coder/inventario-app/actions).

## Seguridad y gestión de secretos

### Secret de Kubernetes

No almacene valores reales de credenciales en el repositorio. `k8s/secret.example.yaml` es únicamente una plantilla documental y `k8s/secret.yaml` está excluido por `.gitignore`.

Antes del despliegue, cree el Secret directamente en el clúster:

```powershell
$env:INVENTARIO_API_KEY = 'clave-ficticia-para-el-laboratorio'
kubectl create secret generic inventario-secret --from-literal=API_KEY=$env:INVENTARIO_API_KEY
kubectl get secret inventario-secret
Remove-Item Env:INVENTARIO_API_KEY
```

El Deployment consume el valor mediante `secretKeyRef`. El endpoint `/version` reporta `secretConfigured: true` y una máscara; nunca devuelve el contenido de `API_KEY`.

### Escaneo de vulnerabilidades

El pipeline usa `aquasecurity/trivy-action` con los siguientes controles:

```yaml
exit-code: '1'
ignore-unfixed: true
vuln-type: 'os,library'
severity: 'CRITICAL'
```

El comportamiento es fail-fast: si Trivy encuentra una vulnerabilidad CRITICAL aplicable, el job falla y la imagen no se publica. Durante la verificación se detectó `CVE-2026-59873` en la dependencia `tar` incluida por npm. La corrección fue eliminar npm de la etapa `runtime`, manteniendo el escaneo activo. El análisis posterior no reportó hallazgos CRITICAL.

## Despliegue base en Kubernetes

El manifiesto [`k8s/deployment.yaml`](k8s/deployment.yaml) implementa:

- Dos réplicas de la aplicación.
- Estrategia `RollingUpdate` con `maxUnavailable: 1` y `maxSurge: 1`.
- `readinessProbe` y `livenessProbe` sobre `/health`.
- `STARTUP_DELAY_SECONDS=10` para comprobar que Kubernetes espera a que la aplicación esté lista.
- Límites y solicitudes de CPU y memoria.

Ejecute el despliegue base después de crear el Secret:

```powershell
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

kubectl rollout status deployment/inventario-app
kubectl get deployment inventario-app
kubectl get pods -l app=inventario-app
kubectl get service inventario-app-service
```

Obtenga la URL del Service y compruebe los endpoints:

```powershell
$url = minikube service inventario-app-service --url
curl.exe "$url/health"
curl.exe "$url/version"
curl.exe "$url/api/products"
```

### Evidencia obtenida en el clúster

| Verificación | Resultado observado |
| --- | --- |
| Rollout base | `deployment/inventario-app successfully rolled out`; 2/2 réplicas disponibles. |
| Imagen promovida | `ghcr.io/kennypallchizaca-coder/inventario-app:a14d7eaf5dbbd322d392af20b5d234a01e68da26`. |
| Salud | `/health` respondió `200` después de completar el arranque lento. |
| Secret | `/version` indicó `secretConfigured: true` sin exponer el valor. |

## Persistencia de datos y estado efímero

La aplicación conserva productos en `data/products.json` dentro del contenedor. Esta ubicación es efímera: al recrearse el Pod, la capa de escritura se pierde. El siguiente procedimiento documenta la observación:

```powershell
# Crear un producto desde la interfaz o mediante la API.
# Elegir un Pod específico y eliminarlo.
$pod = kubectl get pods -l app=inventario-app -o jsonpath='{.items[0].metadata.name}'
kubectl delete pod $pod
kubectl rollout status deployment/inventario-app
```

Evidencia observada: se creó el producto `EVI-20260725`, se eliminó el Pod que lo contenía y el registro no existió en el Pod recreado. Esto no es un fallo de Kubernetes; evidencia que una aplicación de producción debe utilizar un `PersistentVolumeClaim` o una base de datos externa para conservar el estado.

## Estrategia Canary

Canary es la estrategia evaluada. La versión estable (`v1`) tiene cuatro réplicas y la versión Canary (`v2`) tiene una réplica, por lo que el reparto esperado es aproximadamente 80 % y 20 %.

Un detalle importante es el aislamiento del tráfico. Los Pods Canary y el Service correspondiente incluyen la etiqueta `rollout: canary`; esto evita que el Service de prueba reciba tráfico del Deployment base.

```powershell
kubectl apply -f k8s/canary/deployment-v1.yaml
kubectl apply -f k8s/canary/deployment-v2.yaml
kubectl apply -f k8s/canary/service.yaml

kubectl get pods -l app=inventario-app,rollout=canary
$canaryUrl = minikube service inventario-app-canary-service --url
```

Para observar el reparto desde Windows, ejecute:

```powershell
$resultados = 1..100 | ForEach-Object {
  (Invoke-RestMethod "$canaryUrl/version").version
}
$resultados | Group-Object | Select-Object Name, Count
```

### Evidencia Canary

| Elemento | Resultado observado |
| --- | --- |
| Réplicas v1 | 4/4 Pods `Running` y `Ready`. |
| Réplicas v2 | 1/1 Pod `Running` y `Ready`. |
| Prueba de 100 solicitudes | `v1.0.0=83`, `v2.0.0-canary=17`. |
| Conclusión | El reparto observado es coherente con la proporción 4:1. |

Para promover o revertir, escale los Deployments de forma explícita y compruebe el resultado antes de retirar una versión:

```powershell
# Promoción: aumentar v2 y reducir v1 de manera gradual.
kubectl scale deployment inventario-app-v2 --replicas=5
kubectl scale deployment inventario-app-v1 --replicas=0

# Reversión: restaurar v1 y retirar la versión Canary.
kubectl scale deployment inventario-app-v1 --replicas=4
kubectl scale deployment inventario-app-v2 --replicas=0
```

## Estrategia alternativa: Blue-Green

Los manifiestos de [`k8s/blue-green/`](k8s/blue-green/) permiten mantener las versiones Blue y Green desplegadas y conmutar el tráfico mediante el selector del Service.

```powershell
kubectl apply -f k8s/blue-green/deployment-blue.yaml
kubectl apply -f k8s/blue-green/deployment-green.yaml
kubectl apply -f k8s/blue-green/service.yaml

$blueGreenUrl = minikube service inventario-app-bluegreen-service --url
curl.exe "$blueGreenUrl/version"

# Conmutar el Service hacia Green.
kubectl patch service inventario-app-bluegreen-service -p '{"spec":{"selector":{"environment":"green"}}}'
curl.exe "$blueGreenUrl/version"
```

Blue-Green es adecuada cuando se requiere un cambio inmediato y un rollback simple del selector. Canary es preferible cuando se desea observar la nueva versión con una fracción de tráfico antes de una promoción completa.

## Métricas DORA

Las métricas se calcularon a partir de timestamps verificables de Git y de los rollouts de Kubernetes. No se utilizaron valores de ejemplo.

| Métrica | Cálculo | Resultado |
| --- | --- | --- |
| Lead time for changes | `a9a8ca2`: 23m06s; `a14d7ea`: 3m00s. | Promedio: 13m03s. |
| Deployment frequency | Dos promociones exitosas al Deployment base durante la misma jornada. | 2 despliegues/día. |
| Change failure rate | Un intento fallido inicial por imagen inválida, sobre tres intentos reales. | 33.3 %. |

Para auditar los commits y volver a calcular las métricas:

```powershell
git log --format='%H | %aI | %s'
kubectl rollout history deployment/inventario-app
kubectl get events --sort-by=.lastTimestamp
```

## Informes y evidencias entregables

- [Informe final de CI/CD en Word](informe_final_ci_cd.docx): incluye matriz de rúbrica, capturas de la aplicación, CodeSnaps, evidencias de Kubernetes y métricas DORA.
- [Reporte de reflexión en PDF](reporte_reflexion.pdf): contiene el análisis técnico resumido y el contexto de las métricas.
- [Historial de GitHub Actions](https://github.com/kennypallchizaca-coder/inventario-app/actions): evidencia de ejecuciones automáticas del pipeline.

## Comandos de limpieza opcional

Ejecute estos comandos solo cuando finalice la práctica y ya no necesite los recursos del clúster:

```powershell
kubectl delete -f k8s/canary/service.yaml -f k8s/canary/deployment-v2.yaml -f k8s/canary/deployment-v1.yaml
kubectl delete -f k8s/blue-green/service.yaml -f k8s/blue-green/deployment-green.yaml -f k8s/blue-green/deployment-blue.yaml
kubectl delete -f k8s/service.yaml -f k8s/deployment.yaml
kubectl delete secret inventario-secret
```

Antes de eliminar el Secret, confirme que no está siendo utilizado por otro despliegue del mismo namespace.
