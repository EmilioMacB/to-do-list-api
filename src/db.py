"""Capa de datos: credenciales desde Secrets Manager y consultas a PostgreSQL (RDS).

Toda falla al hablar con la base (secret inaccesible, RDS detenida, red, SQL)
se traduce a una sola excepción: DatabaseError. Así main.py no necesita
conocer los detalles de boto3 ni de psycopg.
"""

import json
import logging
import os
from contextlib import contextmanager
from typing import Any, Iterator

import boto3
import psycopg
from botocore.exceptions import BotoCoreError, ClientError
from psycopg.rows import dict_row

import metrics

logger = logging.getLogger("todo-api.db")

CONNECT_TIMEOUT_SECONDS = 3

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS tasks (
    id         SERIAL PRIMARY KEY,
    title      VARCHAR(255) NOT NULL,
    done       BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
"""


class DatabaseError(Exception):
    """Cualquier error al leer o escribir en la base de datos."""


# Errores "esperables" que convertimos en DatabaseError
_EXPECTED_ERRORS = (psycopg.Error, BotoCoreError, ClientError, KeyError, ValueError)


class TaskRepository:
    """Acceso a la tabla `tasks` en RDS."""

    def __init__(self) -> None:
        self._credentials: dict[str, Any] | None = None
        self._schema_ready = False

    # -- Credenciales --------------------------------------------------------

    def _get_credentials(self) -> dict[str, Any]:
        """Lee el secret en runtime (la primera vez) y lo cachea en memoria.

        No hay password en el código ni en variables de ambiente: solo el
        NOMBRE del secret (DB_SECRET_NAME). boto3 se autentica con el rol de
        la EC2 (LabInstanceProfile), sin access keys.
        """
        if self._credentials is None:
            client = boto3.client("secretsmanager")
            response = client.get_secret_value(SecretId=os.environ["DB_SECRET_NAME"])
            self._credentials = json.loads(response["SecretString"])
        return self._credentials

    # -- Conexión ------------------------------------------------------------

    @contextmanager
    def _connection(self) -> Iterator[psycopg.Connection]:
        """Abre una conexión, crea la tabla si hace falta y hace commit al salir.

        Una conexión por petición: más simple que un pool y hace que una caída
        de RDS se detecte de inmediato (útil para la métrica de errores).
        """
        try:
            creds = self._get_credentials()
            with psycopg.connect(
                host=creds["host"],
                port=creds["port"],
                dbname=creds["dbname"],
                user=creds["username"],
                password=creds["password"],
                sslmode="require",
                connect_timeout=CONNECT_TIMEOUT_SECONDS,
                row_factory=dict_row,
            ) as conn:
                if not self._schema_ready:
                    conn.execute(SCHEMA_SQL)
                    self._schema_ready = True
                yield conn
        except _EXPECTED_ERRORS as exc:
            if isinstance(exc, psycopg.OperationalError):
                # Si fue un problema de conexión/credenciales, la próxima vez
                # volvemos a leer el secret (por si cambió el host o el password).
                self._credentials = None
            logger.error("Error de base de datos: %s", exc)
            # Métrica propia #1: cuenta cada lectura/escritura fallida en RDS.
            # Está aquí (y no en main.py) porque es el único punto por donde
            # pasan TODAS las operaciones: GET/POST /tasks y el ping de /health.
            metrics.record_database_error()
            raise DatabaseError(str(exc)) from exc

    # -- Operaciones ---------------------------------------------------------

    def list_tasks(self) -> list[dict[str, Any]]:
        with self._connection() as conn:
            return conn.execute(
                "SELECT id, title, done, created_at FROM tasks ORDER BY id;"
            ).fetchall()

    def create_task(self, title: str, done: bool) -> dict[str, Any]:
        with self._connection() as conn:
            row = conn.execute(
                "INSERT INTO tasks (title, done) VALUES (%s, %s) "
                "RETURNING id, title, done, created_at;",
                (title, done),
            ).fetchone()
            if row is None:  # no debería pasar con RETURNING
                raise DatabaseError("INSERT no regresó la fila creada")
            return row

    def ping(self) -> None:
        """Verifica que la base responda. Lanza DatabaseError si no."""
        with self._connection() as conn:
            conn.execute("SELECT 1;")
