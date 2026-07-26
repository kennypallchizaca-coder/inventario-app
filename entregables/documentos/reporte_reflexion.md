# Examen Final CI/CD | Kenny | 26 de julio de 2026

**Repositorio:** https://github.com/kennypallchizaca-coder/inventario-app

## Estrategia Canary

Se seleccionó Canary para `inventario-app` porque una versión defectuosa puede afectar la consulta y el registro de productos desde la API REST y la interfaz web. La estrategia usa recursos nativos de Kubernetes: un Deployment estable con cuatro réplicas, un Deployment Canary con una y un Service que distribuye conexiones entre los Pods seleccionados por `app: inventario-app`. Las etiquetas `release: stable` y `release: canary` identifican cada grupo.

La relación 4:1 aproxima 80 % estable y 20 % Canary, sin garantizar un porcentaje exacto por solicitud. La evidencia disponible de 100 solicitudes registró 81 respuestas estables y 19 Canary. Antes de repetir la medición, el Deployment base debe escalarse a cero, ya que el Service Canary selecciona solamente `app`. La imagen estable usa una etiqueta SHA comprobada; la del Canary debe reemplazarse por un SHA publicado antes del despliegue.

## Persistencia de datos

La aplicación no usa SQLite. Guarda productos en `data/products.json`, dentro del filesystem del contenedor. Al crear un producto, eliminar el Pod y esperar su recreación, el producto dejó de estar disponible. El resultado es coherente con almacenamiento local efímero. Aumentar réplicas no resuelve la persistencia: cada Pod puede tener una copia JSON distinta e inconsistente. Una solución de producción requeriría PersistentVolume/PersistentVolumeClaim con una estrategia de acceso adecuada o una base de datos externa.

## Métricas DORA

| Métrica | Fórmula | Estado |
| --- | --- | --- |
| Lead time for changes | Hora de despliegue ejecutándose menos hora del commit | Pendiente de evidencia de rollout por SHA. |
| Frecuencia de despliegue | Promociones reales al Deployment durante el periodo | Pendiente de bitácora de promociones. |
| Change failure rate | Correcciones o rollback / total de despliegues x 100 | Pendiente de bitácora de correcciones y rollback. |

Los timestamps de commit pueden verificarse con Git, pero no hay timestamps que relacionen cada SHA con la finalización de un rollout. Por integridad, las métricas DORA no se expresan con valores estimados. Para completarlas se deben conservar `git log`, `kubectl rollout status`, historial del Deployment y eventos del clúster.

## Problemas y soluciones

| Problema | Solución aplicada |
| --- | --- |
| Dockerfile y workflow con Node.js 24. | Se ajustaron a Node.js 22 Alpine. |
| Trivy usaba una referencia mutable. | Se fijó `aquasecurity/trivy-action@v0.36.0`. |
| `/version` exponía una máscara de API_KEY. | Se dejó únicamente `secretConfigured`. |
| Documentación con SQLite y métricas sin trazas de despliegue. | Se corrigió a JSON local y se marcaron los datos DORA pendientes. |

## Conclusión

La práctica integra pruebas, Docker multi-stage, análisis de seguridad, GHCR y Kubernetes con controles de salud. Canary limita la exposición de una versión nueva y la evidencia 81/19 demuestra su reparto aproximado. Para cerrar la trazabilidad de la rúbrica falta recapturar las evidencias afectadas por la configuración corregida y registrar timestamps reales de DORA.
