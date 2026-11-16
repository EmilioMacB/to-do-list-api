"""Métricas propias en CloudWatch (put_metric_data).

Publica dos métricas en el namespace `TodoApi`:
  - DatabaseErrors  (Count)        → cada vez que falla una lectura/escritura en RDS.
  - RequestLatency  (Milliseconds) → duración de cada petición HTTP.

Diseño:
  - "Dispara y olvida": el envío ocurre en un hilo aparte, así la petición del
    usuario no espera a CloudWatch (put_metric_data tarda ~50-100 ms).
  - Una falla al publicar NUNCA rompe la API: solo se registra en el log.
  - Se puede apagar con METRICS_ENABLED=false (los tests lo hacen para no
    llamar a AWS desde GitHub Actions).
  - boto3 se autentica con el rol de la EC2 (LabInstanceProfile), sin llaves.
"""

import logging
import os
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import boto3

logger = logging.getLogger("todo-api.metrics")

NAMESPACE = os.getenv("METRICS_NAMESPACE", "TodoApi")

DATABASE_ERRORS = "DatabaseErrors"
REQUEST_LATENCY = "RequestLatency"

# 2 hilos bastan para el tráfico de la práctica. Si CloudWatch se pone lento,
# los envíos se encolan en memoria en lugar de bloquear las peticiones.
_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="metrics")
_client: Any = None


def enabled() -> bool:
    return os.getenv("METRICS_ENABLED", "true").lower() == "true"


def _get_client() -> Any:
    global _client
    if _client is None:
        _client = boto3.client("cloudwatch")
    return _client


def _send(name: str, value: float, unit: str) -> None:
    try:
        _get_client().put_metric_data(
            Namespace=NAMESPACE,
            MetricData=[{"MetricName": name, "Value": value, "Unit": unit}],
        )
    except Exception as exc:  # noqa: BLE001 — la observabilidad no debe tumbar la app
        logger.warning("No se pudo publicar la métrica %s: %s", name, exc)


def put_metric(name: str, value: float, unit: str = "Count") -> None:
    """Encola el envío de un dato a CloudWatch (no bloquea)."""
    if not enabled():
        return
    _executor.submit(_send, name, value, unit)


def record_database_error() -> None:
    put_metric(DATABASE_ERRORS, 1, "Count")


def record_request_latency(milliseconds: float) -> None:
    put_metric(REQUEST_LATENCY, milliseconds, "Milliseconds")
