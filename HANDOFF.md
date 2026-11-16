# HANDOFF — estado vivo del proyecto

> Leer esto completo al iniciar cualquier sesión/agente. Actualizarlo al terminar.
> Última actualización: 2026-11-16 · Fases 1–4 ✅ · Siguiente: **Fase 5**

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
| 8 | 3 métricas + 3 alarmas + SNS | ❌ | — |
| 9 | Dashboard + health-check cada 5 min | ❌ | — |
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
- [ ] **Fase 5 — CD:** `release.yml` (tag `v*.*.*` → zip → Release) y `deploy.yml` (`release: published` → EC2 descarga, actualiza `APP_VERSION`, `systemctl restart`). 🔁 *Conversación nueva al terminar.*
- [ ] **Fase 6 — Observabilidad:** métrica errores RDS + métrica propia en la app; 3 alarmas + SNS + dashboard en Terraform; `health-check.yml` (cron `*/5`). Probar deteniendo RDS. 🔁 *Conversación nueva al terminar.*
- [ ] **Fase 7 — Evidencia y entrega:** README, capturas (tfstate S3, dashboard, alarma en ALARM, runs de Actions), diagrama, reporte PDF ≤ 2 hojas.

## Acciones manuales del usuario (fuera del código)
- [ ] En cada sesión del lab: pegar credenciales en `~/.aws/credentials` (reemplazar `[default]` completo) y verificar con `aws sts get-caller-identity`.
- [x] Bootstrap hecho: bucket `todo-api-tfstate-839144413811` (cuenta lab `839144413811`); `terraform init -reconfigure -backend-config="bucket=todo-api-tfstate-839144413811"` ✅. State en `s3://.../todo-list-api/terraform.tfstate`.
- [ ] Limpiar el bloque `[profile eb-cli]` de `~/.aws/config` (tiene llaves viejas en texto plano).
- [ ] (Opcional) borrar `terraform/terraform.tfstate*` locales viejos (state vacío, ya destruido).
- [x] GitHub Secrets cargados (2026-11-16). **Renovar en cada sesión del lab** con el loop de `gh secret set` (bitácora Fase 4).
- [ ] Confirmar suscripción SNS en el correo.
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
- (Histórico) Infra de la prueba (EC2 `i-063b2068f517322fb`, RDS `todo-api-db`) quedó **arriba** en el lab; se apaga sola con la sesión. Al reanudar el lab, EC2/RDS arrancan solas (la IP pública cambia); si se borraron, `terraform apply`.

## Siguiente paso exacto
1. ✅ Commits `13077ad` (infra Fase 1) y `d53aa0b` (feat Fase 2) en `main`, pusheados. **Commits sin Co-Authored-By ni atribución a Claude** (preferencia del usuario).
2. ✅ Apply de prueba OK (2026-11-16). La infra puede seguir arriba mientras dure el lab; si se apaga, `terraform apply` la recrea.
3. ✅ Fase 3 (ver bitácora). Correr tests local: `.venv/bin/pytest`.
4. ✅ Fase 4 (ver bitácora). Pendiente del usuario: capturas de los 3 runs en Actions para el reporte.
5. **Fase 5** — `release.yml` + `deploy.yml` (en conversación nueva). La infra está arriba (creada por Provision); `instance_id` y `api_url` con `terraform -chdir=terraform output`.
