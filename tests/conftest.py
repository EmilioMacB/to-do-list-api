"""Fixtures compartidas por los tests.

pytest carga este archivo automáticamente. Aquí definimos un repositorio
FALSO (en memoria) para que los tests no dependan de AWS, RDS ni internet:
así corren en segundos dentro de GitHub Actions y siempre dan el mismo resultado.
"""

from datetime import datetime, timezone
from typing import Any

import pytest
from fastapi.testclient import TestClient

from db import DatabaseError
from main import app, get_repository


class FakeRepository:
    """Imita la interfaz de db.TaskRepository guardando las tareas en una lista.

    Con `fail = True` simula que RDS está caída: cada operación lanza
    DatabaseError, igual que haría el repositorio real.
    """

    def __init__(self) -> None:
        self.tasks: list[dict[str, Any]] = []
        self.fail = False

    def _check(self) -> None:
        if self.fail:
            raise DatabaseError("RDS simulada fuera de servicio")

    def list_tasks(self) -> list[dict[str, Any]]:
        self._check()
        return list(self.tasks)

    def create_task(self, title: str, done: bool) -> dict[str, Any]:
        self._check()
        task = {
            "id": len(self.tasks) + 1,
            "title": title,
            "done": done,
            "created_at": datetime.now(timezone.utc),
        }
        self.tasks.append(task)
        return task

    def ping(self) -> None:
        self._check()


@pytest.fixture
def fake_repo() -> FakeRepository:
    return FakeRepository()


@pytest.fixture
def client(fake_repo: FakeRepository):
    """Cliente HTTP de prueba con el repositorio falso inyectado.

    dependency_overrides le dice a FastAPI: "cuando un endpoint pida
    get_repository, entrégale fake_repo en su lugar". Al terminar el test
    se limpia para que no contamine a los demás.
    """
    app.dependency_overrides[get_repository] = lambda: fake_repo
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
