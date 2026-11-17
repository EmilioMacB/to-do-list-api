# HANDOFF — estado vivo del proyecto

> Leer esto completo al iniciar cualquier sesión/agente. Actualizarlo al terminar.
> Última actualización: 2026-11-17 · Fases 1–7 ✅ · Siguiente: merge del PR de Fase 7, capturas en anexos y entrega

## Estado actual (diagnóstico inicial)

| # | Checklist | Estado | Notas |
|---|---|---|---|
| 1 | Entregables (reporte, diagrama, anexos, repo) | ❌ | Sin README, sin reporte. |
| 2 | Infra 100 % Terraform + tfstate remoto | 🟡 | EC2, SG, RDS sí. **Falta Key Pair** (usa `vockey` existente), **backend remoto** (state local) y `variables.tf` vacío. |
| 3 | Credenciales en Secrets Manager | ❌ | Password **hardcodeado** en `main.tf` (`supersecreto123`, ya está en el historial de GitHub) y pasado como env var en `user_data`. |
| 4 | Workflows provision/destroy manuales | ❌ | No existe `.github/`. |
| 5 | App completa | 🟡 | GET/POST /tasks con RDS ✅. **Faltan `/version` y `/health`**. Usa `tarea` en vez de `title`/`done`. Puerto 3000 (enunciado usa 8000). |
| 6 | ≥ 3 tests en CI + bloqueo de merge | ❌ | Sin tests, sin `ci.yml`, sin branch protection. App no exporta `app` (difícil de testear). |
| 7 | Release por tag + deploy en EC2 | ❌ | Además, la app corre con `nohup` → no hay forma limpia de reiniciarla (necesita systemd). |
| 8 | 3 métricas + 3 alarmas + SNS | ✅ | Fase 6: CPU EC2 (nativa), `TodoApi/DatabaseErrors`, `TodoApi/RequestLatency`; SNS correo confirmado. |
| 9 | Dashboard + health-check cada 5 min | ✅ | `todo-api-dashboard` + `health-check.yml`. Falta solo la captura (Fase 7). |
| 10 | `user_data` clona, instala y levanta | 🟡 | Existe y funciona, pero mete credenciales en texto plano y no usa systemd ni instance profile. |

## Decisiones
- ✅ Lenguaje: **Python + FastAPI + boto3** (cumplir rúbrica literal). El código TS se elimina en Fase 2. Estructura: `src/main.py`, `src/requirements.txt`, `tests/`.
- ✅ El usuario quiere **explicaciones didácticas** de cada cambio (práctica escolar).
- ✅ Backend S3 con **configuración parcial**: el bucket (`todo-api-tfstate-<ACCOUNT_ID>`) se pasa con `terraform init -backend-config="bucket=..."`; lock nativo `use_lockfile` (sin DynamoDB). Bucket creado por `scripts/bootstrap-backend.sh`.
- ✅ El secret JSON `todo-api/db-credentials` tiene `{username,password,host,port,dbname}`; `recovery_window_in_days = 0` para poder recrearlo tras cada destroy.
- ✅ Contrato `user_data` → app (la Fase 2 DEBE respetarlo): código en `/opt/todo-api`, venv en `/opt/todo-api-venv`, servicio systemd `todo-api` corre `uvicorn main:app` desde `/opt/todo-api/src` en puerto 8000, con `EnvironmentFile=/etc/todo-api.env` (`APP_VERSION`, `APP_PORT`, `DB_SECRET_NAME`, `AWS_REGION`). La app debe leer el secret **perezosamente y con reintento** (EC2 y RDS se crean en paralelo).
- ✅ Tag de la EC2: `Name=todo-api-server` (el deploy la buscará por tag o por output `instance_id`).
- Alarmas, SNS y dashboard se crearán **con Terraform**, leyendo `alerting/*.json` (así sobreviven a los resets del lab y cuentan como "archivo de configuración").
- Deploy en EC2 vía **SSM Run Command** (sin SSH) si `LabInstanceProfile` lo permite; fallback: SSH desde Actions con llave en GitHub Secret.
- EC2 obtiene permisos con `iam_instance_profile = "LabInstanceProfile"`.

## Plan por fases (marcar al completar)
- [x] **Fase 1 — Cimientos Terraform** (código ✅, `terraform validate` ✅; falta bootstrap + init en AWS por el usuario; el `apply` real se hace al terminar Fase 2 porque `user_data` instala `src/requirements.txt`): bucket S3 de backend (bootstrap único) + `backend "s3"`; `aws_key_pair`; `random_password` + `aws_secretsmanager_secret(_version)`; `iam_instance_profile`; `variables.tf`/`outputs.tf` completos; `user_data` con servicio **systemd** y sin passwords. 🔁 *Conversación nueva al terminar.*
- [x] **Fase 2 — App** (smoke test local ✅ con repo falso y con repo real sin secret → 503): `src/main.py` (4 endpoints, Pydantic, `Depends(get_repository)` para inyectar un repo falso en tests), `src/db.py` (`TaskRepository`, secret cacheado y re-leído tras `OperationalError`, conexión por petición con `connect_timeout=3`, todo error → `DatabaseError`). `/health` → 200 healthy / 503 unhealthy. Errores de BD en `/tasks` → 503. Código TS eliminado.
  - Punto de enganche Fase 6: los `except DatabaseError` en `main.py` / `db.py::_connection` son donde se publicará la métrica de errores RDS.
  - Nota Fase 3: Starlette avisa que `TestClient` con `httpx` está deprecado → evaluar `httpx2` en `requirements-dev.txt`. Pytest necesita `pythonpath = ["src"]` (imports planos `from db import ...`).
- [x] **Fase 3 — Tests + CI:** 15 tests en `tests/test_main.py` (repo falso vía `dependency_overrides` en `tests/conftest.py`; tests de `db.py` con boto3/psycopg reemplazados por `monkeypatch`). `requirements-dev.txt` (pytest + `httpx2`, que quita el warning de Starlette), `pyproject.toml` (`pythonpath=["src"]`). `.github/workflows/ci.yml`: `pull_request` a main + `workflow_dispatch`, Python 3.12, job/check **`tests`**. Branch protection **estricta** (`enforce_admins=true`, PR obligatorio con 0 aprobaciones, check `tests` requerido) → **ya no se puede pushear directo a main: todo cambio entra por PR**, incluido el HANDOFF.
- [x] **Fase 4 — Workflows de infra** (PR #4, validados en AWS): `provision.yml` (verifica creds con `sts` → `bootstrap-backend.sh` idempotente → init con bucket `todo-api-tfstate-<ACCOUNT_ID>` derivado del Account ID → validate → plan `-out` → apply del plan → espera `/health` hasta 8 min → resumen en `$GITHUB_STEP_SUMMARY`). `destroy.yml` (input `confirm` debe ser `destroy`; si no, el job se salta). Ambos: `concurrency: terraform-state` sin cancelar, creds como env vars desde Secrets (sin action extra), Terraform 1.16.1 con `terraform_wrapper: false`. El bucket del backend nunca se destruye.
  - Ojo: `workflow_dispatch` solo aparece en la pestaña Actions cuando el workflow ya está en `main` → primero merge, luego correr.
- [x] **Fase 5 — CD** (PR #6 + fix PR #7, validado end-to-end: tag `v1.0.1` → Release ✅ → Deploy por evento `release` ✅ → `/version` = `v1.0.1`, `/health` healthy):
  - Lección: `run:` de una línea con `": "` rompe el YAML (GitHub muestra un run fallido de 0 s con el nombre del archivo). **Validar workflows con `actionlint`** (instalado con brew) antes de abrir PR.
  - Releases existentes: `v1.0.0` (sin deploy automático, su `deploy.yml` estaba roto; se puede desplegar a mano con Run workflow) y `v1.0.1` (desplegado).
  - `release.yml`: push de tag `v*.*.*` → valida formato estricto `^v\d+\.\d+\.\d+$` → `git archive --prefix=todo-api/` (solo archivos versionados) → `gh release create --generate-notes --verify-tag` con asset `todo-api-<TAG>.zip`.
  - **Decisión:** el Release se crea con el secret **`RELEASE_TOKEN`** (PAT fine-grained, solo este repo, Contents: Read and write), porque los eventos creados con `GITHUB_TOKEN` no disparan otros workflows y `release: published` nunca llegaría a `deploy.yml`.
  - `deploy.yml`: `release: published` + `workflow_dispatch` (input `tag`, para re-desplegar). Busca la EC2 por tag `Name=todo-api-server` en estado running (no necesita tfstate) → espera agente SSM Online → manda `scripts/deploy-remote.sh` en base64 por **SSM Run Command** (`AWS-RunShellScript`, sin SSH) → espera el estado → valida `GET /version` == tag desde internet. `concurrency: deploy`.
  - `scripts/deploy-remote.sh` (corre como root en la EC2): descarga zip público del release → unzip → `pip install -r` en el venv → mueve `/opt/todo-api` a `/opt/todo-api.prev` y pone el nuevo → `sed APP_VERSION` en `/etc/todo-api.env` → `systemctl restart todo-api` → verifica `/version` local; si falla, **rollback** al `.prev`.
  - 🔁 *Conversación nueva al terminar.*
- [x] **Fase 6 — Observabilidad** (PR #9, release `v1.1.0` desplegado, validado deteniendo RDS):
  - `src/metrics.py`: `put_metric_data` en un `ThreadPoolExecutor` (no bloquea la petición; un fallo al publicar solo se loguea). Namespace `TodoApi`, **sin dimensiones** (así la alarma apunta a una sola serie). `METRICS_ENABLED=false` lo apaga; en tests un fixture autouse de `conftest.py` reemplaza `metrics.put_metric` y anota los datos (`recorded_metrics`).
  - **`DatabaseErrors`** (Count): se publica en el `except` de `db.py::_connection` → cuenta lecturas, escrituras y el ping de `/health`.
  - **`RequestLatency`** (ms): middleware HTTP en `main.py`. Métrica propuesta; justificación para el reporte: refleja la experiencia del usuario y detecta degradación por CPU o por RDS lenta. Línea base medida: promedio ~21 ms, p95 ~140 ms.
  - Nativa: **`AWS/EC2 CPUUtilization`**.
  - `alerting/alarms.json` (incluye campos `justificacion` y `accion` que Terraform mete en la descripción → llegan en el correo) y `alerting/cloudwatch-dashboard.json` (placeholders `${instance_id}`, `${region}`, `${account_id}`). `terraform/monitoring.tf` los lee. **Ojo:** alarms.json se lee con `file()` (no `templatefile`) porque las claves de `for_each` deben conocerse en el plan; el placeholder solo se reemplaza en `dimensions`.
  - Alarmas: CPU > 80 % (3 de 3 × 5 min); RDS errores ≥ 1 (1 de 5 × 1 min, notBreaching); latencia p95 > 1000 ms (2 de 3 × 5 min, notBreaching). `alarm_actions` + `ok_actions` → SNS `todo-api-alerts`.
  - Correo: `var.alert_email` (default `""` → sin suscripción). Va en el GitHub Secret **`ALERT_EMAIL`** → `TF_VAR_alert_email` en `provision.yml`. **Tras cada destroy/provision hay que volver a confirmar la suscripción en el correo.**
  - `health-check.yml`: cron `*/5` + manual, 3 intentos; si las credenciales vencieron o no hay EC2 corriendo → warning y sale sin fallar.
  - **Resultado de la prueba (para la pregunta 3 del reporte):** RDS detenida a las 16:30 (hora local) → `DatabaseErrors` 7-10/min → `todo-api-rds-errores` en ALARM a las 16:31 (correo recibido) → health-check manual en `failure`. Cuando RDS terminó de detenerse, cada petición esperó el `connect_timeout` de 3 s → p95 de latencia 138 → ~3100 ms → `todo-api-latencia-alta` en ALARM a las 16:36. RDS arrancada → `/health` healthy, `rds-errores` volvió a OK a las 16:50.
  - 🔁 *Conversación nueva al terminar.*
- [x] **Fase 7 — Evidencia y entrega** (rama `docs/fase-7-entrega`):
  - `README.md`: endpoints, cómo correr en local, secrets, crear/destruir infra (Actions y local), CI/CD, observabilidad.
  - `docs/arquitectura.svg` (fuente, se ve en el README) + `docs/arquitectura.png` (para el PDF; regenerar con `rsvg-convert -z 2 docs/arquitectura.svg -o docs/arquitectura.png`).
  - Reporte **fuera del repo** en `Sesion_5/entrega/`: `reporte.html` (fuente editable) → `reporte.pdf` (2 hojas de cuerpo + 1 de anexos con espacios para capturas). Regenerar: Chrome headless `--print-to-pdf`. Pregunta 3 respondida con la alarma `todo-api-rds-errores` (datos de la prueba de Fase 6).
  - Pendiente del usuario: pegar capturas (tfstate S3, dashboard, alarma en ALARM) en los anexos y exportar el PDF final.

## Acciones manuales del usuario (fuera del código)
- [ ] En cada sesión del lab: pegar credenciales en `~/.aws/credentials` (reemplazar `[default]` completo) y verificar con `aws sts get-caller-identity`.
- [x] Bootstrap hecho: bucket `todo-api-tfstate-839144413811` (cuenta lab `839144413811`); `terraform init -reconfigure -backend-config="bucket=todo-api-tfstate-839144413811"` ✅. State en `s3://.../todo-list-api/terraform.tfstate`.
- [ ] Limpiar el bloque `[profile eb-cli]` de `~/.aws/config` (tiene llaves viejas en texto plano).
- [ ] (Opcional) borrar `terraform/terraform.tfstate*` locales viejos (state vacío, ya destruido).
- [x] GitHub Secrets cargados (2026-11-16). **Renovar en cada sesión del lab** con el loop de `gh secret set` (bitácora Fase 4).
- [x] Confirmar suscripción SNS en el correo (2026-11-16). Repetir tras cada destroy/provision.
- [x] Secret `ALERT_EMAIL` creado (2026-11-16).
- [x] Capturas de dashboard y alarma en ALARM tomadas (2026-11-16).
- [x] Crear PAT fine-grained (repo `to-do-list-api`, Contents: Read and write) y guardarlo como secret `RELEASE_TOKEN` (no expira con el lab; sí con la fecha que le pongas al PAT).
- [x] Branch protection activada con `gh api` (2026-11-16).
- [x] Captura de evidencia: PR #2 (test roto → `BLOCKED`) capturado y cerrado sin merge.
- [x] VS Code: el workspace abierto es `Sesion_5/` (padre del repo), por eso no detectaba `todo-app/.venv`. Se creó `Sesion_5/.vscode/settings.json` (fuera del repo) con `python.defaultInterpreterPath` apuntando al venv.

## Bitácora
- 2026-11-15 — Diagnóstico inicial y creación de `CLAUDE.md`, `HANDOFF.md`, `docs/ENUNCIADO.md`.
- 2026-11-15 — Fase 1: reescritos `main.tf` (backend S3, key pair TLS, random_password, Secrets Manager, LabInstanceProfile, Ubuntu 24.04), `variables.tf`, `outputs.tf`; nuevo `user_data.sh.tftpl` (venv + systemd); `scripts/bootstrap-backend.sh`; `.gitignore`s actualizados. Sin commit aún.

- 2026-11-15 — Fase 2: app FastAPI en `src/`, TS eliminado, `.venv/` local creado.

- 2026-11-16 — Prueba real en AWS: bootstrap S3 + init + apply (9 recursos, RDS ~5 min). Al terminar el apply la API ya respondía: `/health` 200 `database: OK`, `/version` = `d53aa0b` (commit, aún sin tags), POST /tasks 201, validación 422, GET /tasks 200. Agregado `tfplan`/`*.tfplan` a `terraform/.gitignore` (el plan guardado contiene el password).

- 2026-11-16 — Fase 3: tests (15 ✅ local y en Actions, 15 s) + `ci.yml` + branch protection. Entró por PR #1 (rebase-merge). PR #2 = demo de bloqueo, cerrado.
- 2026-11-16 — Fase 4: escritos `provision.yml` y `destroy.yml` en rama `ci/workflows-infra` (sin commit aún). Secrets se cargan con `gh secret set NOMBRE -R EmilioMacB/to-do-list-api --body "$(aws configure get NOMBRE_EN_MINUSCULAS)"`.
- 2026-11-16 — Fase 4 validada: PR #4 mergeado. Run Provision #1 → `No changes` + `/health` OK (comparte state S3 con el apply local). Destroy → 9 recursos borrados. Provision #2 desde cero → 9 añadidos en ~5 min, `/health` healthy al primer intento, `version` = `9d85452`. Infra queda **arriba** (nueva EC2/IP).
- 2026-11-16 — Fase 5: confirmado que SSM Run Command funciona en el Learner Lab (agente Online en Ubuntu 24.04, `send-command` permitido, corre como root). Escritos `release.yml`, `deploy.yml`, `scripts/deploy-remote.sh`. Prueba en seco del script en la EC2 `i-0defde2d53f691d9c` (zip subido a S3 con URL prefirmada, ya borrado) → Success, `/version` = `v0.9.0`, `/health` healthy.
- 2026-11-16 — Fase 5 validada: PR #6 mergeado; tag `v1.0.0` → Release OK pero Deploy no corrió (YAML inválido); fix en PR #7; tag `v1.0.1` → Release (9 s) → Deploy por evento `release` (20 s) → `/version` = `v1.0.1`. Infra sigue **arriba** (EC2 `i-0defde2d53f691d9c`, IP 44.201.213.129).
- (Histórico) Infra de la prueba (EC2 `i-063b2068f517322fb`, RDS `todo-api-db`) quedó **arriba** en el lab; se apaga sola con la sesión. Al reanudar el lab, EC2/RDS arrancan solas (la IP pública cambia); si se borraron, `terraform apply`.

- 2026-11-16 — Fase 6: PR #9 mergeado → Provision (6 recursos añadidos, EC2/RDS sin cambios, IP igual) → tag `v1.1.0` → Deploy OK. Prueba deteniendo RDS exitosa (ver Fase 6). Infra **arriba** (EC2 `i-0defde2d53f691d9c`, IP 44.201.213.129, RDS arrancada).

- 2026-11-17 — Nueva sesión del lab: secrets AWS renovados; EC2 `i-0defde2d53f691d9c` y RDS arrancaron solas (nueva IP 54.197.14.186), `/version` = `v1.1.0`, `/health` healthy. 3 alarmas en OK. `health-check.yml` ya corre por `schedule` (GitHub lo espacia: 3 runs en ~17 h). Fase 7: README, diagrama y reporte.

## Siguiente paso exacto
1. ✅ Commits `13077ad` (infra Fase 1) y `d53aa0b` (feat Fase 2) en `main`, pusheados. **Commits sin Co-Authored-By ni atribución a Claude** (preferencia del usuario).
2. ✅ Apply de prueba OK (2026-11-16). La infra puede seguir arriba mientras dure el lab; si se apaga, `terraform apply` la recrea.
3. ✅ Fase 3 (ver bitácora). Correr tests local: `.venv/bin/pytest`.
4. ✅ Fase 4 (ver bitácora). Pendiente del usuario: capturas de los 3 runs en Actions para el reporte.
5. ✅ Fase 5 (ver bitácora). Para publicar una versión: `git switch main && git pull && git tag vX.Y.Z && git push origin vX.Y.Z`.
6. ✅ Fase 6 (ver bitácora). Verificar en la pestaña Actions que el cron de `health-check.yml` ya corre solo (los `schedule` nuevos tardan en arrancar la primera vez).
8. **Ahora:** merge del PR `docs/fase-7-entrega`; el usuario toma la captura del tfstate en S3, pega las 3 capturas en `Sesion_5/entrega/reporte.pdf` (anexos) y entrega PDF + link del repo.
7. ✅ **Fase 7 — Evidencia y entrega**: README (cómo correr, crear y destruir la infra), diagrama, reporte PDF ≤ 2 hojas (justificaciones de umbrales en `alerting/alarms.json`), captura del tfstate en S3. Nota anterior de Fase 6: Puntos de enganche de la métrica de errores RDS: los `except DatabaseError` en `src/main.py` / `src/db.py::_connection`. El usuario solo quiere capturas que pida la rúbrica (dashboard, alarma en ALARM, tfstate S3). Nota: la EC2 actual usa `user_data` viejo; si Fase 6 toca `user_data`/EC2, Terraform la recreará (nueva IP) y el código vendrá de `git clone` de main (versión = hash) hasta el siguiente tag.
