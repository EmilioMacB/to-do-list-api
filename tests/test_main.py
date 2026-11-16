"""Tests de la API. Corren con: .venv/bin/pytest

Cada test sigue el patrón Arrange / Act / Assert:
preparar el estado → hacer la petición → verificar la respuesta.
"""

import psycopg
import pytest
from botocore.exceptions import ClientError

import db
from db import DatabaseError, TaskRepository

# --- /health ------------------------------------------------------------------


def test_health_ok_when_database_responds(client):
    response = client.get("/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "healthy"
    assert body["database"] == "OK"
    assert "timestamp" in body


def test_health_returns_503_when_database_is_down(client, fake_repo):
    fake_repo.fail = True

    response = client.get("/health")

    # 503 (y no 200 con "FAIL") para que el health-check de Actions lo detecte
    assert response.status_code == 503
    assert response.json()["status"] == "unhealthy"
    assert response.json()["database"] == "FAIL"


# --- /version -----------------------------------------------------------------


def test_version_reads_app_version_env_var(client, monkeypatch):
    # monkeypatch cambia la variable solo durante este test
    monkeypatch.setenv("APP_VERSION", "v1.2.3")

    response = client.get("/version")

    assert response.status_code == 200
    assert response.json() == {"version": "v1.2.3"}


def test_version_defaults_to_dev_without_env_var(client, monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)

    assert client.get("/version").json() == {"version": "dev"}


# --- /tasks -------------------------------------------------------------------


def test_create_task_returns_201_with_id(client):
    response = client.post("/tasks", json={"title": "estudiar", "done": False})

    assert response.status_code == 201
    body = response.json()
    assert body["id"] == 1
    assert body["title"] == "estudiar"
    assert body["done"] is False
    assert "created_at" in body


def test_create_task_done_defaults_to_false(client):
    response = client.post("/tasks", json={"title": "sin done"})

    assert response.status_code == 201
    assert response.json()["done"] is False


@pytest.mark.parametrize(
    "payload",
    [
        {"title": ""},                 # título vacío
        {"done": True},                # falta el título
        {"title": "x" * 256},          # excede 255 caracteres
        {"title": "ok", "done": "tal vez"},  # done no es booleano
    ],
)
def test_create_task_rejects_invalid_payload(client, fake_repo, payload):
    response = client.post("/tasks", json=payload)

    assert response.status_code == 422
    assert fake_repo.tasks == []  # no se guardó nada


def test_list_tasks_returns_created_tasks(client):
    client.post("/tasks", json={"title": "uno"})
    client.post("/tasks", json={"title": "dos", "done": True})

    response = client.get("/tasks")

    assert response.status_code == 200
    assert [t["title"] for t in response.json()] == ["uno", "dos"]
    assert response.json()[1]["done"] is True


@pytest.mark.parametrize(
    "method, path, kwargs",
    [
        ("get", "/tasks", {}),
        ("post", "/tasks", {"json": {"title": "x"}}),
    ],
)
def test_tasks_return_503_when_database_is_down(client, fake_repo, method, path, kwargs):
    fake_repo.fail = True

    response = getattr(client, method)(path, **kwargs)

    assert response.status_code == 503


# --- db.TaskRepository (sin AWS: se reemplazan boto3 y psycopg) ---------------


class _FakeSecretsClient:
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error
        self.calls = 0

    def get_secret_value(self, SecretId):  # noqa: N803 (nombre de boto3)
        self.calls += 1
        if self.error:
            raise self.error
        return {
            "SecretString": '{"host": "h", "port": 5432, "dbname": "d",'
            ' "username": "u", "password": "p"}'
        }


def test_repository_wraps_secrets_manager_errors(monkeypatch):
    error = ClientError({"Error": {"Code": "AccessDeniedException"}}, "GetSecretValue")
    monkeypatch.setattr(db.boto3, "client", lambda *_a, **_k: _FakeSecretsClient(error))
    monkeypatch.setenv("DB_SECRET_NAME", "todo-api/db-credentials")

    with pytest.raises(DatabaseError):
        TaskRepository().ping()


def test_repository_rereads_secret_after_connection_error(monkeypatch):
    secrets = _FakeSecretsClient()
    monkeypatch.setattr(db.boto3, "client", lambda *_a, **_k: secrets)
    monkeypatch.setenv("DB_SECRET_NAME", "todo-api/db-credentials")

    def connect_fails(**_kwargs):
        raise psycopg.OperationalError("connection refused")

    monkeypatch.setattr(db.psycopg, "connect", connect_fails)
    repo = TaskRepository()

    for _ in range(2):
        with pytest.raises(DatabaseError):
            repo.ping()

    # Tras un OperationalError se descarta el secret cacheado → se lee de nuevo
    assert secrets.calls == 2


def test_demo_falla_a_proposito(client):
    """DEMO para el reporte: este PR NO se debe mergear."""
    assert client.get("/version").json() == {"version": "esto-no-es-la-version"}
