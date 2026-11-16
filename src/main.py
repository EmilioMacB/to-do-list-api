"""To-Do List API — FastAPI + PostgreSQL (RDS) + Secrets Manager.

Ejecutar local:  cd src && uvicorn main:app --reload --port 8000
Docs interactivas: http://localhost:8000/docs
"""

import logging
import os
from datetime import datetime, timezone
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from db import DatabaseError, TaskRepository

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

app = FastAPI(title="To-Do List API", description="Práctica 4 — CI/CD + Observabilidad")

# --- Dependencias ------------------------------------------------------------
# FastAPI inyecta el repositorio en cada endpoint. En los tests se reemplaza
# por uno falso con app.dependency_overrides, sin tocar AWS ni RDS.

_repository = TaskRepository()


def get_repository() -> TaskRepository:
    return _repository


Repository = Annotated[TaskRepository, Depends(get_repository)]


def get_version() -> str:
    """Versión desplegada. La define el deploy en /etc/todo-api.env."""
    return os.getenv("APP_VERSION", "dev")


# --- Modelos (validación automática de entrada/salida) ------------------------


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=255, examples=["estudiar para el examen"])
    done: bool = False


class Task(TaskCreate):
    id: int
    created_at: datetime


# --- Endpoints ----------------------------------------------------------------


@app.get("/tasks", response_model=list[Task])
def list_tasks(repo: Repository):
    try:
        return repo.list_tasks()
    except DatabaseError:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "No se pudieron leer las tareas")


@app.post("/tasks", response_model=Task, status_code=status.HTTP_201_CREATED)
def create_task(task: TaskCreate, repo: Repository):
    try:
        return repo.create_task(task.title, task.done)
    except DatabaseError:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "No se pudo guardar la tarea")


@app.get("/version")
def version():
    return {"version": get_version()}


@app.get("/health")
def health(repo: Repository):
    """200 si la base responde, 503 si no (así el health-check de Actions detecta la falla)."""
    try:
        repo.ping()
        database = "OK"
    except DatabaseError:
        database = "FAIL"

    healthy = database == "OK"
    return JSONResponse(
        status_code=status.HTTP_200_OK if healthy else status.HTTP_503_SERVICE_UNAVAILABLE,
        content={
            "status": "healthy" if healthy else "unhealthy",
            "database": database,
            "version": get_version(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    )
