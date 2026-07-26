# Manual de Demostracion en Vivo, Guion de Presentacion y Banco de Preguntas de Defensa

Este documento es el manual maestro para la presentacion oral y demostracion en vivo del laboratorio inventario-app. Incluye el guion exacto paso a paso con los comandos a ejecutar, las observaciones de pantalla, las explicaciones verbales para el evaluador, la matriz de rubrica y las 10 preguntas de examen mas frecuentes con sus respuestas exactas.

Nota: Este archivo es para uso personal de consulta durante la presentacion y esta ignorado por Git.

---

## PARTE 1: GUION DE DEMOSTRACION EN VIVO (PASO A PASO)

---

### Demostracion 1: Pruebas Unitarias Locales y Docker Multi-Stage

Comandos a ejecutar en PowerShell:
```powershell
# 1. Ejecutar pruebas unitarias locales
npm ci
npm test

# 2. Construir la imagen Docker multi-stage
docker build -t inventario-app:local .

# 3. Probar ejecucion local del contenedor
docker run -d --name app-prueba -p 3000:3000 inventario-app:local
curl.exe http://localhost:3000/health
curl.exe http://localhost:3000/version
docker stop app-prueba && docker rm app-prueba
```

Que mostrar en pantalla al profesor:
- En npm test: La consola muestra 6 pass, 0 fail indicando que todas las pruebas automatizadas pasan correctamente.
- En docker build: Señalar las dos etapas en consola: Etapa 1 (build-test corriendo npm test) y Etapa 2 (runtime basada en node:22-alpine con USER node).

Que decir en voz alta:
> "Para el Paso 2 de la Parte I, construimos un Dockerfile Multi-Stage. En la primera etapa 'build-test' instalamos dependencias y ejecutamos la suite de pruebas unitarias. Si alguna prueba falla, Docker aborta la construccion inmediatamente aplicando el principio Fail-Fast. La segunda etapa genera una imagen ligera de produccion (~120 MB) ejecutada bajo el usuario no privilegiado 'node' para mayor seguridad."

---

### Demostracion 2: Pipeline CI/CD en GitHub Actions y Escaneo Trivy

Pasos a mostrar en el navegador web:
1. Entrar al repositorio en GitHub -> Pestaña Actions.
2. Abrir la ultima ejecucion del workflow CI-CD Inventario App.

Que mostrar en pantalla al profesor:
- Job build-test completado en verde (npm ci y npm test).
- Job build-push desplegado. Abrir el paso Escaneo de seguridad de la imagen con Trivy.
- Mostrar que Trivy escanea buscando vulnerabilidades CRITICAL y que esta configurado con exit-code: 1.
- Abrir GitHub Container Registry (GHCR) y mostrar las etiquetas :latest y :SHA.

Que decir en voz alta:
> "Para el Paso 3 y el Componente Adicional de Escaneo de Seguridad, implementamos un workflow en GitHub Actions con dos trabajos encadenados. 'build-push' solo se ejecuta si 'build-test' fue exitoso. Antes de publicar la imagen en GHCR, la accion aquasecurity/trivy-action escanea la imagen local. Si se detectara una vulnerabilidad de severidad CRITICAL sin parche, el pipeline falla con exit-code 1 e impide publicar imagenes inseguras."

---

### Demostracion 3: Kubernetes Base, RollingUpdate y Secretos

Comandos a ejecutar en PowerShell:
```powershell
# 1. Crear el Secret en Minikube
kubectl create secret generic inventario-app-secret --from-literal=API_KEY="super-secret-api-key-12345"

# 2. Desplegar el Deployment base y Service
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# 3. Confirmar estado del rollout
kubectl rollout status deployment/inventario-app
kubectl get deployments,pods,services

# 4. FORMA MAS FACIL DE DEMOSTRAR EL SECRET EN VIVO (Leer API_KEY del pod)
kubectl exec (kubectl get pod -l app=inventario-app -o jsonpath='{.items[0].metadata.name}') -- printenv API_KEY
```

Que mostrar en pantalla al profesor:
- La consola imprime directamente la clave: super-secret-api-key-12345.
- kubectl rollout status muestra el despliegue completado con 2/2 replicas disponibles.

Que decir en voz alta:
> "Para el Paso 4 y el Componente Adicional de Secretos, creamos un Secret nativo en Kubernetes llamado 'inventario-app-secret'. En el Deployment inyectamos la variable API_KEY mediante secretKeyRef. Con este comando demostramos en vivo que la aplicacion lee la clave desde las variables de entorno del contenedor sin que ninguna credencial haya sido escrita en Git."

---

### Demostracion 4: Perdida de Datos al Eliminar un Pod (Paso 5)

Comandos a ejecutar en PowerShell:
```powershell
# 1. Obtener la URL del servicio y crear un producto
$url = minikube service inventario-app-service --url
curl.exe -X POST "$url/api/products" -H "Content-Type: application/json" -d '{"name":"Teclado Demo","sku":"DEMO-999","stock":5,"price":50}'

# 2. Verificar que el producto existe
curl.exe "$url/api/products"

# 3. Eliminar forzosamente uno de los pods del Deployment
$pod = (kubectl get pods -l app=inventario-app -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $pod --grace-period=0 --force

# 4. Esperar a que el pod sea recreado por K8s y consultar la API
curl.exe "$url/api/products"
```

Que mostrar en pantalla al profesor:
- En el primer curl /api/products se observa el producto Teclado Demo.
- Tras eliminar el pod y consultar de nuevo, el producto ha desaparecido del JSON devuelto.

Que decir en voz alta:
> "Esta es la observacion del Paso 5. La aplicacion guarda los productos en 'data/products.json' dentro del sistema de archivos local del contenedor. Como los pods en Kubernetes son efimeros, al eliminar el pod se destruye su capa de almacenamiento local. Kubernetes recrea una instancia limpia desde la imagen base de Docker sin el producto creado. En produccion esto se solucionaria mediante un PersistentVolumeClaim (PVC) o una base de datos externa."

---

### Demostracion 5: Estrategia Canary (Reparto Proporcional 80/20)

Comandos a ejecutar en PowerShell:
```powershell
# 1. Escalar deployment base a 0 y aplicar manifiestos Canary
kubectl scale deployment inventario-app --replicas=0
kubectl apply -f k8s/canary/deployment-stable.yaml
kubectl apply -f k8s/canary/deployment-canary.yaml
kubectl apply -f k8s/canary/service.yaml

# 2. Verificar que existen 5 pods (4 estables + 1 canary)
kubectl get pods -l app=inventario-app

# 3. Ejecutar 100 peticiones en bucle para comprobar el balanceo
$canaryUrl = minikube service inventario-app-canary-service --url
$respuestas = 1..100 | ForEach-Object { (Invoke-RestMethod "$canaryUrl/version").release }
$respuestas | Group-Object | Select-Object Name, Count
```

Que mostrar en pantalla al profesor:
- kubectl get pods muestra 4 pods con release: stable y 1 pod con release: canary.
- El conteo de las 100 peticiones devuelve aprox. 80 respuestas stable y 20 respuestas canary.

Que decir en voz alta:
> "Para los Pasos 6 al 8 elegimos la estrategia Canary utilizando recursos nativos de Kubernetes. Desplegamos 4 replicas estables y 1 replica canary. Como el Service selecciona el label comun 'app: inventario-app', Kubernetes distribuye las conexiones round-robin, entregando un 80% de trafico a la version estable y un 20% a la version Canary sin necesidad de usar herramientas externas como Argo Rollouts."

---

### Demostracion 6: Estrategia Blue-Green (Conmutacion Instantanea)

Comandos a ejecutar en PowerShell:
```powershell
# 1. Desplegar manifiestos Blue-Green
kubectl apply -f k8s/blue-green/deployment-blue.yaml
kubectl apply -f k8s/blue-green/deployment-green.yaml
kubectl apply -f k8s/blue-green/service.yaml

# 2. Verificar version actual (Blue)
$bgUrl = minikube service inventario-app-bluegreen-service --url
curl.exe "$bgUrl/version"

# 3. Conmutar el selector del Service a 'environment: green'
kubectl patch service inventario-app-bluegreen-service -p '{"spec":{"selector":{"environment":"green"}}}'

# 4. Verificar version inmediata (Green)
curl.exe "$bgUrl/version"
```

Que mostrar en pantalla al profesor:
- Antes del patch: /version devuelve color: blue.
- Despues del patch: /version devuelve inmediatamente color: green.

Que decir en voz alta:
> "Tambien dejamos implementada la estrategia Blue-Green en 'k8s/blue-green/'. Al parchear la etiqueta 'environment: green' en el Service, todo el trafico del cluster conmuta al 100% de la version Blue a la Green en milisegundos sin reiniciar pods."

---

### Demostracion 7: Readiness con Arranque Lento (STARTUP_DELAY_SECONDS)

Comandos a ejecutar en PowerShell:
```powershell
# 1. Probar localmente en Docker simulando 10 segundos de inicio
docker run -d -p 3000:3000 -e STARTUP_DELAY_SECONDS=10 --name slow-app inventario-app:local

# 2. Consultar /health inmediatamente (primeros 10 segundos)
curl.exe -i http://localhost:3000/health

# 3. Esperar 10 segundos y consultar de nuevo
Start-Sleep -Seconds 10
curl.exe -i http://localhost:3000/health
docker stop slow-app && docker rm slow-app
```

Que mostrar en pantalla al profesor:
- Durante los primeros 10s: /health devuelve HTTP/1.1 503 Service Unavailable con status: not-ready.
- Despues de 10s: /health devuelve HTTP/1.1 200 OK con status: ok.

Que decir en voz alta:
> "Para el Componente Adicional 3, agregamos 'STARTUP_DELAY_SECONDS=10' en 'server.js'. Durante los primeros 10 segundos la app responde 503 notificando que esta iniciando. En Kubernetes calibramos el startupProbe y readinessProbe para conceder el tiempo de gracia necesario. Si en lugar de ajustar los probes simplemente aumentaramos las replicas, todas las replicas fallarian a los 3s entrando en CrashLoopBackOff masivo."

---

### Demostracion 8: Informe PDF y Metricas DORA (Parte II)

Accion:
Abrir el documento reporte_reflexion.pdf (o entregables/documentos/reporte_reflexion.pdf).

Que mostrar en pantalla al profesor:
- La tabla de Metricas DORA:
  - Lead Time for Changes: 4 min 24 s (Alto / Elite).
  - Deployment Frequency: 1.67 despliegues / dia (Alto).
  - Change Failure Rate: 20% (Medio).
- Las secciones de Justificacion de Canary, Perdida de Datos en JSON y Bitacora de Errores Reales.

Que decir en voz alta:
> "En la Parte II calculamos nuestras metricas DORA midiendo los timestamps reales de commits de Git y rollouts en el cluster. Registramos un Lead Time promedio de 4 minutos 24 segundos, una frecuencia de 1.67 despliegues diarios y una tasa de fallos del 20%, ubicando a nuestro equipo en el nivel de High Performance."

---

## PARTE 2: MATRIZ DE CUMPLIMIENTO DE LA RUBRICA

### Bloque A — Parte I: Construccion y Despliegue (70 Puntos)

| Dimension | Criterio de Evalucion | Puntaje Maximo | Estado | Implementacion y Ubicacion |
| --- | --- | --- | --- | --- |
| **Pipeline base construido desde cero** | Dockerfile multi-stage, workflow de CI/CD funcional publicando en ghcr.io, y Deployment + Service con rolling update, todo desplegado sobre el cluster real. | **25 pts** | **Completo (25/25)** | • `Dockerfile`: Multi-stage (`build-test` + `runtime` en `node:22-alpine` con `USER node`).<br/>• `.github/workflows/ci-cd.yml`: Jobs `build-test` y `build-push` publicando en `ghcr.io` con `:latest` y `:SHA`.<br/>• `k8s/deployment.yaml`: 2 replicas, `RollingUpdate` (`maxUnavailable: 1`, `maxSurge: 1`), probes en `/health`.<br/>• `k8s/service.yaml`: Service NodePort. |
| **Segunda estrategia de despliegue** | Blue-Green o Canary esta correctamente implementada sobre el cluster real, con evidencia clara del corte o reparto de trafico. | **25 pts** | **Completo (25/25)** | • **Canary (Elegida)**: `k8s/canary/` con 4 replicas estables y 1 canary realizando reparto proporcional 80% / 20%.<br/>• **Blue-Green**: Manifiestos en `k8s/blue-green/` con conmutacion instantanea. |
| **Componentes adicionales obligatorios (2 de 3)** | Al menos dos de los tres componentes (secretos, escaneo CI, readiness lento) funcionando con evidencia real. | **20 pts + 2 pts extra** | **Completo (22/20)** | **¡Se implementaron los 3 componentes para el bono de +2 pts!**<br/>1. *Secretos*: `k8s/secret.yaml` + `secretKeyRef` para `API_KEY`.<br/>2. *Escaneo CI*: Trivy Action en `ci-cd.yml` fallando en `CRITICAL` (`exit-code: 1`).<br/>3. *Arranque Lento*: `STARTUP_DELAY_SECONDS=10` y probes calibrados. |

### Bloque B — Parte II: Pruebas y el Informe (30 Puntos)

| Dimension | Criterio de Evaluacion | Puntaje Maximo | Estado | Implementacion y Ubicacion |
| --- | --- | --- | --- | --- |
| **Justificacion de la estrategia elegida** | Eleccion entre Blue-Green y Canary argumentada tecnicamente para el caso especifico de esta aplicacion. | **10 pts** | **Completo (10/10)** | Argumentacion tecnica de Canary: menor uso de computo (ahorro del 80% frente a duplicar pods en Blue-Green), mitigacion gradual de riesgos en API REST y rollback inmediato. |
| **Metricas propias** | Lead time, frecuencia y change failure rate calculados a partir de datos propios verificables con reflexion DORA. | **10 pts** | **Completo (10/10)** | Calculos con timestamps reales de Git y Minikube:<br/>• **Lead Time**: 4 min 24 s (Alto/Elite).<br/>• **Frecuencia**: 1.67 despliegues/dia (Alto).<br/>• **Failure Rate**: 20% (Medio). |
| **Documentacion y claridad general** | README e informe de reflexion redactados con claridad, permitiendo reproducir el trabajo a un tercero. | **10 pts** | **Completo (10/10)** | • `README.md`: Documentacion tecnica profesional de ingenieria.<br/>• `reporte_reflexion.pdf`: Informe de 2 paginas completo.<br/>• `entregables/`: Estructura limpia de entregables. |

---

## PARTE 3: JUSTIFICACION TECNICA DE CONFIGURACIONES

| Decision de Configuracion | Justificacion Tecnica |
|---|---|
| Base Docker node:22-alpine | Reduce el tamaño de la imagen final a ~120 MB, eliminando binarios innecesarios y reduciendo la superficie de vulnerabilidades CVE. |
| Build Multi-Stage | Separa el contexto de compilacion/pruebas del ejecutable final. Permite aplicar el principio fail-fast (si npm test falla en la etapa 1, Docker detiene la generacion de la imagen). |
| USER node en Dockerfile | Principio de menor privilegio. Evita ejecutar la aplicacion como root dentro del contenedor, protegiendo al host de ataques de escape de contenedor. |
| Fail-Fast en CI/CD (needs: build-test) | El job build-push depende explicitamente de que build-test pase. Evita gastar computo en empaquetar y subir imagenes defectuosas a GHCR. |
| Escaneo Trivy con severity: CRITICAL | Analiza librerias del sistema operativo y de npm antes de publicar. exit-code: 1 garantiza que ninguna imagen con vulnerabilidades criticas conocidas llegue al registro. |
| Estrategia Canary (80/20) | Ideal para servicios REST de catalogo. Permite exponer la nueva version a un 20% del publico sin requerir duplicar la infraestructura como en Blue-Green (ahorro de computo del 80%). |
| Manejo de Secretos con secretKeyRef | Evita la fuga de secretos en codigo fuente (CWE-798). Las credenciales reales se inyectan en runtime por la API de Kubernetes. |
| Readiness Probe Tuning (initialDelay: 5, threshold: 5) | Permite tolerar aplicaciones con inicializacion pesada (ej. STARTUP_DELAY_SECONDS=10) sin que Kubernetes marque el pod como Unhealthy y entre en CrashLoopBackOff. |

---

## PARTE 4: BANCO DE PREGUNTAS Y RESPUESTAS DE DEFENSA (FAQ DE EXAMEN)

### P1: ¿Por que eligieron la estrategia Canary sobre Blue-Green para inventario-app?
> **Respuesta:** "Elegimos Canary porque para una API de inventario es mas eficiente en recursos. Blue-Green requiere duplicar el 100% de la capacidad de computo (200% en total) mientras duran los despliegues. Canary nos permite desplegar la version nueva en 1 sola replica frente a 4 estables (reparto 80/20), reduciendo el impacto del riesgo a una fraccion del trafico sin sobrecargar el cluster."

### P2: ¿Por que se perdieron los datos del producto al borrar el pod en el Paso 5?
> **Respuesta:** "Porque 'db.js' almacena los productos en un archivo JSON local ('data/products.json') dentro de la capa de escritura del contenedor. Los pods en Kubernetes son efimeros e inmutables: al eliminar el pod, su almacenamiento local se destruye. En produccion esto se resuelve montando un PersistentVolumeClaim (PVC) o integrando una base de datos externa como PostgreSQL o MongoDB."

### P3: ¿Que pasaria si en lugar de ajustar los probes de readiness aumentamos las replicas durante un arranque lento?
> **Respuesta:** "Aumentar replicas empeoraria la situacion. Si las replicas tardan 10 segundos en iniciar y el probe falla a los 3 segundos, Kubernetes asumira que todos los pods estan defectuosos y los matara consecutivamente, causando un CrashLoopBackOff masivo sin atender trafico. La solucion correcta es calibrar 'startupProbe' e 'initialDelaySeconds' en el readinessProbe."

### P4: ¿Como garantiza Kubernetes cero downtime durante un RollingUpdate?
> **Respuesta:** "A traves de 'maxUnavailable: 1' y 'maxSurge: 1' junto con el 'readinessProbe'. K8s crea 1 pod nuevo primero. El Service NO envia trafico al pod nuevo hasta que su readinessProbe responde HTTP 200 OK. Recien cuando el pod nuevo esta listo, K8s elimina 1 pod de la version anterior, manteniendo disponibilidad continua."

### P5: ¿Como funciona el escaneo de Trivy en el pipeline de GitHub Actions?
> **Respuesta:** "Trivy analiza la imagen construida buscando CVEs conocidos en paquetes Alpine y dependencias npm. Con 'severity: CRITICAL' y 'exit-code: 1', si encuentra vulnerabilidades de alta gravedad sin parche, la accion devuelve codigo de salida 1 y GitHub Actions detiene el pipeline inmediatamente antes de subir la imagen a GHCR."

### P6: ¿Como obtienen o verifican la API_KEY configurada en Kubernetes?
> **Respuesta:** "Ejecutando `kubectl exec (kubectl get pod -l app=inventario-app -o jsonpath='{.items[0].metadata.name}') -- printenv API_KEY`. La clave es inyectada desde el Secret 'inventario-app-secret' via 'secretKeyRef' directamente al entorno del contenedor sin haber quedado escrita en Git."

### P7: ¿Como se calcularon las metricas DORA y en que nivel ubican al equipo?
> **Respuesta:** 
> - **Lead Time for Changes (4 min 24 s):** Tiempo entre el commit de Git y la ejecucion de `kubectl set image` en el cluster (Nivel Alto/Elite).
> - **Deployment Frequency (1.67 despliegues/dia):** Promociones realizadas por dia de desarrollo (Nivel Alto).
> - **Change Failure Rate (20%):** Porcentaje de despliegues que requirieron correccion posterior (Nivel Medio).

### P8: ¿Por que usan 'USER node' en el Dockerfile?
> **Respuesta:** "Por el principio de menor privilegio. Por defecto los contenedores corren como 'root'. Si un atacante logra explotar una vulnerabilidad de ejecucion remota de codigo en Node.js, tendria acceso root dentro del contenedor. Al cambiar al usuario 'node', limitamos la superficie de impacto."

### P9: ¿Por que en Git subieron 'secret.example.yaml' y no 'secret.yaml'?
> **Respuesta:** "Por buenas practicas de DevSecOps. Las credenciales reales nunca deben estar escritas en texto plano en archivos versionados en Git (CWE-798). En el repositorio se incluye la plantilla 'secret.example.yaml', y el Secret real se crea en el cluster con `kubectl create secret`."

### P10: ¿Como logra Kubernetes el reparto de trafico 80/20 en Canary sin Argo Rollouts?
> **Respuesta:** "Aprovechando que un Service de Kubernetes distribuye conexiones en formato round-robin de forma proporcional a la cantidad de pods que matchean su selector 'app: inventario-app'. Al tener 4 pods estables y 1 pod canary compartiendo el mismo selector, por probabilidad matematica el 80% de conexiones llega a la version estable y el 20% a la version canary."
