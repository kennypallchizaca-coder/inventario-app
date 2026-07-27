# inventario-app: Practica Final de CI/CD, Kubernetes y Metricas DORA

Repositorio del proyecto de construccion, automatizacion y orquestacion de una aplicacion web de inventario basada en Node.js/Express con persistencia local JSON. El proyecto abarca la implementacion integral de un pipeline de Integracion y Entrega Continua (CI/CD), contenerizacion segura, despliegue en Kubernetes (Minikube) con estrategias progresivas, controles de seguridad DevSecOps y evaluacion cuantitativa mediante metricas DORA.

---

## 1. Entorno de Desarrollo Local y Pruebas Unitarias

La aplicacion expone una API REST y una interfaz web estatica. Para garantizar la calidad del codigo antes de cualquier empaquetado, la suite de pruebas unitarias valida la integridad de los endpoints principales.

### Instalacion y Ejecucion Local

```powershell
# Instalacion limpia de dependencias
npm ci

# Ejecucion de la suite de pruebas unitarias
npm test

# Inicio del servidor en entorno local (Puerto 3000)
npm start
```

### Rutas y Endpoints de Diagnostico

Con el servidor en ejecucion, los endpoints principales se verifican mediante las siguientes peticiones:

```powershell
curl.exe -i http://localhost:3000/
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

- `GET /health`: Devuelve `503 Service Unavailable` (`status: not-ready`) durante el periodo de arranque simulado y `200 OK` (`status: ok`) cuando la aplicacion se encuentra operativa.
- `GET /version`: Retorna la version, el color identificador de la réplica y confirma si las credenciales secretas fueron inyectadas correctamente (`secretConfigured: true`), sin exponer valores sensibles.
- `GET /api/products`: Retorna el listado de productos almacenados en el catalogo.

---

## 2. Contenerizacion Multi-Stage con Docker

El archivo `Dockerfile` adopta un diseño multi-stage sobre la imagen base `node:22-alpine` para maximizar la seguridad y minimizar el tamaño final de los contenedores.

### Estructura de las Etapas de Construccion

1. **Etapa 1 (`build-test`)**: Instala las dependencias mediante `npm ci` y ejecuta inmediatamente `npm test`. Si alguna prueba falla, la construccion de la imagen se detiene de forma automatica (principio *Fail-Fast*), impidiendo la generacion de artefactos defectuosos.
2. **Etapa 2 (`runtime`)**: Construye la imagen final de produccion copiando unicamente las dependencias compiladas y los archivos necesarios de la aplicacion. La ejecucion se delega al usuario no privilegiado `USER node` para reducir la superficie de ataque dentro del contenedor.

### Comandos de Construccion y Verificacion Contenerizada

```powershell
# Construccion de la imagen Docker
docker build -t inventario-app:local .

# Ejecucion del contenedor en segundo plano
docker run -d --name inventario-app-local -p 3000:3000 inventario-app:local

# Verificacion de salud y endpoints
curl.exe http://localhost:3000/health
curl.exe http://localhost:3000/version
curl.exe http://localhost:3000/api/products

# Limpieza del contenedor de prueba
docker stop inventario-app-local
docker rm inventario-app-local
```

---

## 3. Pipeline de CI/CD y Escaneo de Seguridad (Trivy)

El workflow automatizado en `.github/workflows/ci-cd.yml` gestiona el flujo de integracion y despliegue continuo en GitHub Actions.

### Estructura del Workflow

- **Job `build-test`**: Ejecuta las pruebas unitarias en un entorno Node.js 22.
- **Job `build-push`**: Depende estrictamente del exito de `build-test`. Construye la imagen con Docker Buildx y ejecuta un escaneo de seguridad mediante `aquasecurity/trivy-action`.
- **Control de Seguridad Trivy**: Configurado con `severity: CRITICAL` y `exit-code: 1`. Si Trivy detecta vulnerabilidades de severidad critica sin parche, el paso falla e interrumpe la publicacion.
- **Publicacion en Registro (GHCR)**: Una vez aprobado el analisis de seguridad, la imagen se publica en GitHub Container Registry (`ghcr.io`) bajo las etiquetas `:latest` y con el SHA inmutable del commit (`:${{ github.sha }}`).

---

## 4. Despliegue Base en Kubernetes y Gestion de Secretos

### Gestion de Secretos (DevSecOps)

Las credenciales no se versionan en Git. En el repositorio se incluye la plantilla `k8s/secret.example.yaml` y la credencial real se inyecta directamente en el clúster:

```powershell
# Creacion del Secret en Minikube
kubectl create secret generic inventario-app-secret --from-literal=API_KEY="super-secret-api-key-12345"
```

El manifiesto `k8s/deployment.yaml` consume este secreto mediante `secretKeyRef`, inyectando `API_KEY` como variable de entorno en runtime.

### Despliegue Base con RollingUpdate

El despliegue base especifica 2 replicas y una estrategia `RollingUpdate` (`maxUnavailable: 1`, `maxSurge: 1`) que garantiza la disponibilidad continua durante las actualizaciones:

```powershell
# Aplicar despliegue base y servicio
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Confirmar estado del rollout
kubectl rollout status deployment/inventario-app
kubectl get deployments,pods,services

# Probar acceso al servicio
$url = minikube service inventario-app-service --url
curl.exe "$url/health"
curl.exe "$url/version"
```

### Simulacion de Arranque Lento (`STARTUP_DELAY_SECONDS`)

La variable `STARTUP_DELAY_SECONDS=10` simula una inicializacion pesada de la aplicacion. Para tolerar este comportamiento sin que Kubernetes reinicie los pods de forma prematura:
- `startupProbe`: Otorga una ventana de inicializacion de hasta 40 segundos (`periodSeconds: 2`, `failureThreshold: 20`).
- `readinessProbe`: Inicia la verificacion periodica una vez superado el arranque.

*Analisis de Ingenieria*: Aumentar el numero de replicas sin calibrar los probes no resuelve el problema de arranque lento; por el contrario, todas las replicas fallarian el diagnostico simultaneamente, provocando un estado de `CrashLoopBackOff` masivo.

---

## 5. Segunda Estrategia de Despliegue: Canary Nativo

Se implemento la estrategia **Canary** aprovechando los mecanismos nativos de enrutamiento de Kubernetes (Deployment + Service), sin herramientas adicionales como Argo Rollouts.

### Estructura de Manifiestos Canary

- `k8s/canary/deployment-stable.yaml`: 4 replicas corriendo la version estable (`release: stable`).
- `k8s/canary/deployment-canary.yaml`: 1 replica corriendo la version candidata (`release: canary`).
- `k8s/canary/service.yaml`: Service NodePort con selector comun `app: inventario-app`.

### Ejecucion y Verificacion del Reparto de Trafico (80/20)

Al compartir el selector `app: inventario-app`, el Service distribuye las conexiones de forma proporcional a la cantidad de pods activos (4 estables vs 1 canary):

```powershell
# Reemplazar el selector base y aplicar despliegue Canary
kubectl scale deployment inventario-app --replicas=0
kubectl apply -f k8s/canary/deployment-stable.yaml
kubectl apply -f k8s/canary/deployment-canary.yaml
kubectl apply -f k8s/canary/service.yaml

# Verificar el reparto proporcional ejecutando 100 peticiones
$canaryUrl = minikube service inventario-app-canary-service --url
$respuestas = 1..100 | ForEach-Object { (Invoke-RestMethod "$canaryUrl/version").release }
$respuestas | Group-Object | Select-Object Name, Count
```

El resultado esperado refleja aproximadamente un 80% de respuestas `stable` y un 20% de respuestas `canary`, demostrando la mitigacion progresiva del riesgo antes de una promocion completa.

---

## 6. Analisis de Persistencia de Datos y Estado Efimero

La aplicacion almacena los productos en `data/products.json` dentro del sistema de archivos local del contenedor.

### Experimento de Eliminacion de Pod

```powershell
# 1. Crear un producto mediante la API
curl.exe -X POST "$url/api/products" -H "Content-Type: application/json" -d '{"name":"Teclado Mecanico","sku":"KEY-001","stock":10,"price":85}'

# 2. Eliminar el pod ejecutor
$pod = (kubectl get pods -l app=inventario-app -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $pod --grace-period=0 --force

# 3. Consultar la API nuevamente
curl.exe "$url/api/products"
```

### Diagnostico Tecnico

Al eliminar el pod, Kubernetes crea una nueva replica basada en la imagen limpia de Docker. Como la capa de escritura del contenedor es efimera, **el producto creado desaparece**. En arquitecturas de produccion, la persistencia se garantiza mediante un `PersistentVolumeClaim` (PVC) montado en la ruta de datos o migrando el estado hacia una base de datos relacional/NoSQL externa.

---

## 7. Evaluacion Cuantitativa con Metricas DORA

Las metricas DORA se calcularon utilizando timestamps reales extraidos del historial de commits de Git y de los eventos de despliegue en Minikube:

| Metrica DORA | Formula y Datos Medicion | Resultado Calculado | Clasificacion DORA |
| --- | --- | --- | --- |
| **Lead Time for Changes** | Tiempo desde el commit hasta el rollout exitoso en el cluster.<br/>• Cambio 1: 4m 32s<br/>• Cambio 2: 4m 15s | **4 min 24 s** (Promedio) | **Alto / Elite** (< 1 hora) |
| **Deployment Frequency** | Frecuencia de promociones exitosas al cluster por dia.<br/>• 5 promociones en 3 dias de trabajo. | **1.67 despliegues / dia** | **Alto** (Cadencia diaria) |
| **Change Failure Rate** | Porcentaje de despliegues que requirieron correccion o rollback.<br/>• 1 fallo inicial (probe timeout) en 5 despliegues. | **20 %** | **Medio** (15% - 46%) |

---

## 8. Resolucion de Desafios de Ingenieria

1. **Compatibilidad Multiplataforma en Dockerfile**: Se normalizo el archivo a `Dockerfile` con mayuscula inicial para evitar fallos de sensibilidad a mayusculas en los runners Linux de GitHub Actions.
2. **Calibracion de Probes de Diagnostico**: Se introdujo `startupProbe` y se ajusto `initialDelaySeconds: 5` y `failureThreshold: 5` en el `readinessProbe` para evitar bucles de `CrashLoopBackOff` durante el arranque de 10 segundos.
3. **Permisos de Registro GHCR**: Se asignaron permisos explicitos `packages: write` en el workflow de CI/CD para autorizar la autenticacion y publicacion segura de imagenes en GitHub Container Registry.
