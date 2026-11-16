# Práctica 4: To-Do List (CI/CD + Observabilidad) — Enunciado

> Fuente de verdad de los requisitos. Consultar solo cuando haga falta el detalle; el resumen operativo está en `CLAUDE.md`.

## 1.1 La aplicación
API to-do-list con tareas persistidas en **RDS**.

| Endpoint | Descripción |
|---|---|
| `GET /tasks` | Lista de tareas registradas |
| `POST /tasks` | Crea una tarea nueva |
| `GET /version` | Versión desplegada, leída de una **variable de ambiente** |
| `GET /health` | Verifica conexión a BD (OK/FAIL) + versión + timestamp del servidor |

Ejemplo de validación:
```bash
curl -X POST http://<ip-ec2>:8000/tasks -H "Content-Type: application/json" \
  -d '{"title": "estudiar para el examen de desarrollo en la nube", "done": false}'
curl http://<ip-ec2>:8000/tasks
```

## 1.2 Infraestructura como código (Terraform)
- `main.tf`, `variables.tf`, `outputs.tf` crean **EC2 + Security Group + Key Pair**.
- `user_data`: al arrancar clona el repo, instala dependencias y levanta la app. **Sin SSH ni scp.**
- Terraform también crea **RDS** y un **secret en Secrets Manager** con las credenciales; la app lo lee **en tiempo de ejecución**.
- **tfstate en backend remoto** (S3 o HCP). Nunca en el repo.

## 1.3 Continuous Integration
- ≥ 3 pruebas unitarias.
- Workflow de CI disparado al **abrir un Pull Request**; corre las pruebas.
- Configurar el repo para que **solo se pueda hacer merge a `main` si pasan** (branch protection / ruleset).

## 1.4 Continuous Delivery & Deployment
- **Release:** push de tag `v#.#.#` → workflow crea un **GitHub Release con el repo en zip**.
- **Deploy:** al **publicarse un release** → workflow descarga el artefacto en la EC2 y reinicia el servidor.
- Validar con `GET /version` después de cada deploy.

## 1.5 Observabilidad (CloudWatch)
**Métricas (≥ 3):**
1. Una **nativa de AWS** (no requiere instrumentación).
2. Una propia con `put_metric_data` (boto3) que cuente **errores al leer/escribir en RDS**. Validar **deteniendo RDS**.
3. Otra propia, propuesta por ti, sobre el comportamiento de la app (justificar en el reporte).

**Alarmas:** una por métrica (3). Umbral + periodo de evaluación justificados; acción esperada si se dispara. **Notificación por correo** vía tópico **SNS** (suscripción confirmada) conectado a las 3.

**Dashboard:** CloudWatch dashboard con las 3 métricas.

## 1.6 Estructura sugerida
```
to-do-list-api/
├── src/ (main.py, requirements.txt)
├── tests/test_main.py
├── .github/workflows/ provision.yml destroy.yml ci.yml release.yml deploy.yml health-check.yml
├── terraform/ main.tf variables.tf outputs.tf
├── alerting/ cloudwatch-dashboard.json alarms.json
└── README.md
```

## 2 Entregables
**Reporte PDF** (máx. 2 hojas, sin portada): nombre, materia, fecha; descripción breve + **diagrama de arquitectura**; reflexión:
1. Ventaja concreta de Terraform vs. a mano/bash; algo que hubiera costado más sin Terraform; relación y diferencias entre `scp` y `user_data`.
2. ¿Qué pasos manuales dejaste de hacer con el pipeline y qué riesgo corrías antes?
3. De las 3 alarmas, elige una: ¿qué situación real la dispararía, cómo la diagnosticas con el dashboard, qué acción tomarías?

**Anexos (capturas):** dashboard en AWS · una alarma en trigger · tfstate en S3/HCP.

**Repositorio GitHub** con README: código instrumentado; workflows (provision, destroy, CI, release, deploy, health monitor); config del dashboard y alarmas; README con cómo correr, crear y destruir la infra.

Evidencia = ejecuciones de workflows en GitHub Actions + capturas. No se pide video.

## 3 Checklist de revisión (10 pts c/u)
1. Entregables completos (reporte, diagrama, anexos, respuestas, repo).
2. Infra 100% Terraform (EC2, SG, Key Pair, RDS). tfstate remoto, fuera del repo. **Sin captura de S3/HCP = 0.**
3. Credenciales RDS en Secrets Manager, leídas en runtime, no hardcodeadas.
4. Workflows provision/destroy con **trigger manual**, corren exitosamente.
5. App completa: GET/POST /tasks persisten en RDS; /version; /health (BD, versión, timestamp).
6. ≥ 3 tests en CI al abrir PR, **bloquean merge** a main si fallan.
7. Tag `v#.#.#` → Release; Release → deploy en EC2.
8. 3 métricas (1 nativa, 2 propias incl. errores RDS) + 1 alarma c/u → SNS correo. **Sin captura de alarma = 0.**
9. Dashboard con las 3 métricas + workflow que monitorea `/health` **cada 5 min**. **Sin captura del dashboard = 0.**
10. EC2 arranca con `user_data` que clona, instala y levanta la app sin intervención manual.
