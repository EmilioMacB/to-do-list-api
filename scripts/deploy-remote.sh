#!/bin/bash
# =============================================================================
# Se ejecuta DENTRO de la EC2, como root, enviado por .github/workflows/deploy.yml
# a través de SSM Run Command (sin SSH). No correrlo a mano.
#
# Variables que inyecta el workflow:
#   TAG        versión a desplegar (ej. v1.0.0)
#   ASSET_URL  URL pública del zip adjunto al GitHub Release
#
# Respeta el contrato de user_data: código en /opt/todo-api, venv en
# /opt/todo-api-venv, config en /etc/todo-api.env, servicio systemd todo-api.
# =============================================================================
set -euo pipefail
: "${TAG:?falta TAG}" "${ASSET_URL:?falta ASSET_URL}"

APP_DIR=/opt/todo-api
PREV_DIR=/opt/todo-api.prev
VENV_DIR=/opt/todo-api-venv
ENV_FILE=/etc/todo-api.env
PORT=$(grep -E '^APP_PORT=' "$ENV_FILE" | cut -d= -f2 || true)
PORT=${PORT:-8000}
PREV_VERSION=$(grep -E '^APP_VERSION=' "$ENV_FILE" | cut -d= -f2 || true)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> 1/6 Descargando ${ASSET_URL}"
curl -fsSL --retry 3 -o "$WORK/release.zip" "$ASSET_URL"

echo "==> 2/6 Descomprimiendo"
unzip -q "$WORK/release.zip" -d "$WORK"
NEW_DIR="$WORK/todo-api"            # el zip trae todo dentro de todo-api/
test -f "$NEW_DIR/src/main.py" || { echo "El zip no contiene src/main.py"; exit 1; }

echo "==> 3/6 Instalando dependencias en el venv"
"$VENV_DIR/bin/pip" install --quiet --disable-pip-version-check -r "$NEW_DIR/src/requirements.txt"

echo "==> 4/6 Reemplazando el código (la versión anterior queda en ${PREV_DIR})"
rm -rf "$PREV_DIR"
mv "$APP_DIR" "$PREV_DIR"
mv "$NEW_DIR" "$APP_DIR"
chown -R ubuntu:ubuntu "$APP_DIR"

set_version() {
  if grep -qE '^APP_VERSION=' "$ENV_FILE"; then
    sed -i "s/^APP_VERSION=.*/APP_VERSION=$1/" "$ENV_FILE"
  else
    echo "APP_VERSION=$1" >> "$ENV_FILE"
  fi
}

echo "==> 5/6 APP_VERSION=${TAG} y reinicio del servicio"
set_version "$TAG"
systemctl restart todo-api

echo "==> 6/6 Verificando /version en localhost"
for i in $(seq 1 20); do
  # -fs sin -S: los primeros intentos fallan mientras uvicorn arranca; no ensuciar el log
  if curl -fs --max-time 3 "http://127.0.0.1:${PORT}/version" | grep -q "\"${TAG}\""; then
    echo "OK: la API responde con la versión ${TAG}"
    exit 0
  fi
  sleep 2
done

# --- Rollback: la versión nueva no levantó; volvemos a la anterior ----------
echo "ERROR: la API no respondió con ${TAG}. Últimos logs del servicio:"
journalctl -u todo-api -n 40 --no-pager || true
echo "==> Rollback a ${PREV_VERSION:-versión anterior}"
rm -rf "$APP_DIR"
mv "$PREV_DIR" "$APP_DIR"
set_version "$PREV_VERSION"
systemctl restart todo-api
exit 1
