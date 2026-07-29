# Evidencia reproducible de métricas DORA

Medición realizada el 29 de julio de 2026 sobre el contexto `minikube`, en el namespace aislado `inventario-final`. Las dos imágenes están publicadas en GHCR y cada promoción terminó con `kubectl rollout status` exitoso.

## Timestamps de los commits

```text
SHA=a14d7eaf5dbbd322d392af20b5d234a01e68da26
COMMIT_TIME=2026-07-25T14:02:22-05:00
SUBJECT=fix: reducir superficie de la imagen de ejecucion

SHA=23462bfbdb23c22b3d028f6e8edab0831165fc05
COMMIT_TIME=2026-07-26T23:35:10-05:00
SUBJECT=docs: actualizar README.md redactado como estudiante destacado sin evidencias
```

Los timestamps anteriores se reproducen con:

```powershell
git show -s --format="SHA=%H%nCOMMIT_TIME=%cI%nSUBJECT=%s" a14d7eaf5dbbd322d392af20b5d234a01e68da26
git show -s --format="SHA=%H%nCOMMIT_TIME=%cI%nSUBJECT=%s" 23462bfbdb23c22b3d028f6e8edab0831165fc05
```

## Promoción 1

```powershell
kubectl --context minikube -n inventario-final apply -f k8s/deployment.yaml
kubectl --context minikube -n inventario-final rollout status deployment/inventario-app --timeout=5m
```

```text
SHA=a14d7eaf5dbbd322d392af20b5d234a01e68da26
COMMIT_TIME=2026-07-25T14:02:22-05:00
DEPLOY_START_UTC=2026-07-29T18:09:17.0662700Z
deployment "inventario-app" successfully rolled out
ROLLOUT_EXIT=0
ROLLOUT_COMPLETE_UTC=2026-07-29T18:09:29.6695805Z
K8S_CONDITION_TIME=2026-07-29T18:09:29Z
RUNNING_IMAGE=ghcr.io/kennypallchizaca-coder/inventario-app:a14d7eaf5dbbd322d392af20b5d234a01e68da26
READY=2/2
```

Lead time 1: desde `2026-07-25T19:02:22Z` hasta `2026-07-29T18:09:29Z` = **95 h 07 min 07 s**.

## Promoción 2

```powershell
kubectl --context minikube -n inventario-final set image deployment/inventario-app inventario-app=ghcr.io/kennypallchizaca-coder/inventario-app:23462bfbdb23c22b3d028f6e8edab0831165fc05
kubectl --context minikube -n inventario-final rollout status deployment/inventario-app --timeout=5m
```

```text
SHA=23462bfbdb23c22b3d028f6e8edab0831165fc05
COMMIT_TIME=2026-07-26T23:35:10-05:00
DEPLOY_START_UTC=2026-07-29T18:09:42.3445692Z
deployment "inventario-app" successfully rolled out
ROLLOUT_EXIT=0
ROLLOUT_COMPLETE_UTC=2026-07-29T18:09:58.9297591Z
K8S_CONDITION_TIME=2026-07-29T18:09:58Z
RUNNING_IMAGE=ghcr.io/kennypallchizaca-coder/inventario-app:23462bfbdb23c22b3d028f6e8edab0831165fc05
READY=2/2
```

Lead time 2: desde `2026-07-27T04:35:10Z` hasta `2026-07-29T18:09:58Z` = **61 h 34 min 48 s**.

## Historial y verificación funcional

```text
REVISION  CHANGE-CAUSE
1         Promocion controlada SHA a14d7eaf5dbbd322d392af20b5d234a01e68da26
2         Promocion controlada SHA 23462bfbdb23c22b3d028f6e8edab0831165fc05

UTC=2026-07-29T18:10:20.8624718Z
Health=ok
Version=v1
Color=blue
SecretConfigured=True
Products=3
```

## Cálculos finales

| Métrica | Cálculo | Resultado | Nivel según la tabla de clase |
| --- | --- | --- | --- |
| Lead time for changes | `(95:07:07 + 61:34:48) / 2` | **78 h 20 min 58 s** | Alto: entre un día y una semana |
| Deployment frequency | `2 promociones exitosas / 1 día de medición` | **2 despliegues por día** | Alto: cadencia diaria |
| Change failure rate | `0 promociones con rollback o corrección / 2 × 100` | **0 %** | Alto/élite: menor al 15 % |

La ventana controlada contiene dos promociones reales y ninguna requirió rollback o corrección posterior. Las ejecuciones fallidas de CI se conservan como evidencia de mejora del pipeline, pero no se cuentan como despliegues al clúster.
