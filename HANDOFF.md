# HANDOFF — estado vivo del proyecto

> Leer esto completo al iniciar cualquier sesión/agente. Actualizarlo al terminar.
> Última actualización: 2026-11-16 · Fases 1 y 2: **validadas en AWS** (apply ✅, endpoints ✅) · Siguiente: **Fase 3**

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
- [ ] **Fase 3 — Tests + CI:** ≥ 3 tests (BD mockeada), `ci.yml` en `pull_request`, branch protection en `main` con status check requerido. 🔁 *Conversación nueva al terminar.*
- [ ] **Fase 4 — Workflows de infra:** `provision.yml` / `destroy.yml` con `workflow_dispatch`, credenciales del lab en Secrets.
- [ ] **Fase 5 — CD:** `release.yml` (tag `v*.*.*` → zip → Release) y `deploy.yml` (`release: published` → EC2 descarga, actualiza `APP_VERSION`, `systemctl restart`). 🔁 *Conversación nueva al terminar.*
- [ ] **Fase 6 — Observabilidad:** métrica errores RDS + métrica propia en la app; 3 alarmas + SNS + dashboard en Terraform; `health-check.yml` (cron `*/5`). Probar deteniendo RDS. 🔁 *Conversación nueva al terminar.*
- [ ] **Fase 7 — Evidencia y entrega:** README, capturas (tfstate S3, dashboard, alarma en ALARM, runs de Actions), diagrama, reporte PDF ≤ 2 hojas.

## Acciones manuales del usuario (fuera del código)
- [ ] En cada sesión del lab: pegar credenciales en `~/.aws/credentials` (reemplazar `[default]` completo) y verificar con `aws sts get-caller-identity`.
- [x] Bootstrap hecho: bucket `todo-api-tfstate-839144413811` (cuenta lab `839144413811`); `terraform init -reconfigure -backend-config="bucket=todo-api-tfstate-839144413811"` ✅. State en `s3://.../todo-list-api/terraform.tfstate`.
- [ ] Limpiar el bloque `[profile eb-cli]` de `~/.aws/config` (tiene llaves viejas en texto plano).
- [ ] (Opcional) borrar `terraform/terraform.tfstate*` locales viejos (state vacío, ya destruido).
- [ ] GitHub Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (renovar cada sesión del lab).
- [ ] Confirmar suscripción SNS en el correo.
- [ ] Activar branch protection en GitHub (o hacerlo con `gh api`).

## Bitácora
- 2026-11-15 — Diagnóstico inicial y creación de `CLAUDE.md`, `HANDOFF.md`, `docs/ENUNCIADO.md`.
- 2026-11-15 — Fase 1: reescritos `main.tf` (backend S3, key pair TLS, random_password, Secrets Manager, LabInstanceProfile, Ubuntu 24.04), `variables.tf`, `outputs.tf`; nuevo `user_data.sh.tftpl` (venv + systemd); `scripts/bootstrap-backend.sh`; `.gitignore`s actualizados. Sin commit aún.

- 2026-11-15 — Fase 2: app FastAPI en `src/`, TS eliminado, `.venv/` local creado.

- 2026-11-16 — Prueba real en AWS: bootstrap S3 + init + apply (9 recursos, RDS ~5 min). Al terminar el apply la API ya respondía: `/health` 200 `database: OK`, `/version` = `d53aa0b` (commit, aún sin tags), POST /tasks 201, validación 422, GET /tasks 200. Agregado `tfplan`/`*.tfplan` a `terraform/.gitignore` (el plan guardado contiene el password).

## Siguiente paso exacto
1. ✅ Commits `13077ad` (infra Fase 1) y `d53aa0b` (feat Fase 2) en `main`, pusheados. **Commits sin Co-Authored-By ni atribución a Claude** (preferencia del usuario).
2. ✅ Apply de prueba OK (2026-11-16). La infra puede seguir arriba mientras dure el lab; si se apaga, `terraform apply` la recrea.
3. Pendiente commit: `terraform/.gitignore` + `HANDOFF.md`/`CLAUDE.md`.
4. **Fase 3** — tests + CI + branch protection.
