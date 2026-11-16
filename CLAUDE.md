# CLAUDE.md — to-do-list-api (Práctica 4: CI/CD + Observabilidad)

Este archivo se carga en cada sesión. Mantenerlo corto. El estado vivo está en `HANDOFF.md`; los requisitos completos en `docs/ENUNCIADO.md`.

## Protocolo de trabajo (todo agente)
1. **Al iniciar:** leer `HANDOFF.md` completo. Solo abrir `docs/ENUNCIADO.md` si necesitas el detalle de un requisito.
2. **Trabajar una sola fase** del plan a la vez (ver HANDOFF). No adelantar fases.
3. **Al terminar o pausar:** actualizar `HANDOFF.md` (estado, decisiones, bloqueos, siguiente paso exacto) antes de cerrar.
4. Si se termina una fase grande, recomendar al usuario **abrir una conversación nueva** (contexto fresco) — el HANDOFF es lo que hereda el siguiente agente.
5. Idioma: español. Commits con Conventional Commits en español (`feat:`, `fix:`, `ci:`, `infra:`, `docs:`, `test:`).
6. No hacer commit/push ni correr `terraform apply/destroy` sin pedirlo al usuario.

## Stack
- App: **Python 3.12 + FastAPI + psycopg 3 + boto3** en `src/` (`main.py` = HTTP, `db.py` = datos/secret). Venv local: `.venv/`. Correr: `cd src && ../.venv/bin/uvicorn main:app --reload --port 8000`.
- El usuario quiere **explicaciones didácticas** de cada cambio (qué y por qué), en español.
- Infra: Terraform (AWS provider ~> 5.0), región `us-east-1`, **AWS Academy Learner Lab**.
- CI/CD: GitHub Actions. Repo: `EmilioMacB/to-do-list-api`, rama `main`.
- Observabilidad: CloudWatch (métricas, alarmas, dashboard) + SNS (email).

## Restricciones del Learner Lab (críticas)
- **No se pueden crear roles IAM.** Usar el instance profile existente `LabInstanceProfile` (rol `LabRole`) en la EC2 para leer Secrets Manager y hacer `PutMetricData`.
- Credenciales temporales: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, **`AWS_SESSION_TOKEN`**. Expiran con la sesión → **actualizar los GitHub Secrets en cada sesión del lab** antes de correr workflows.
- La sesión dura ~4 h (el enunciado dice 2 h); los recursos se detienen. Asumir que la infra se recrea seguido → todo debe ser idempotente y reproducible desde cero.
- El bucket S3 del backend de Terraform se crea **una sola vez** fuera de este Terraform (bootstrap), porque el backend no puede gestionarse a sí mismo.

## Reglas de oro (se pierden puntos si se rompen)
- **Nada de secretos en el repo**: ni passwords en `.tf`, ni `terraform.tfstate`, ni llaves `.pem`. Usar `random_password` + Secrets Manager.
- La app lee las credenciales de RDS **desde Secrets Manager en runtime** (SDK), no de variables con el password.
- `GET /version` lee una **variable de ambiente** (`APP_VERSION`) que el deploy actualiza con el tag del release.
- Todo recurso (EC2, SG, Key Pair, RDS, Secret, SNS, alarmas, dashboard) se crea con Terraform.
- Cero SSH/scp manual. El arranque es 100 % `user_data`; el deploy es 100 % workflow.

## Comandos útiles
```bash
# Terraform (desde terraform/)
terraform init            # usa backend S3 remoto
terraform plan
terraform output -raw public_ip

# Validar la app
IP=$(terraform -chdir=terraform output -raw public_ip)
curl http://$IP:<puerto>/health
curl http://$IP:<puerto>/version
curl -X POST http://$IP:<puerto>/tasks -H "Content-Type: application/json" -d '{"title":"demo","done":false}'
```

## Mapa de archivos objetivo
```
.github/workflows/{ci,provision,destroy,release,deploy,health-check}.yml
terraform/{main,variables,outputs,backend?,monitoring?}.tf
alerting/{cloudwatch-dashboard.json,alarms.json}
src/  tests/  docs/  README.md  HANDOFF.md
```
