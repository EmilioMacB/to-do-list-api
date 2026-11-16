#!/usr/bin/env bash
# =============================================================================
# Crea (una sola vez) el bucket S3 que guarda el tfstate de Terraform.
# Va fuera de Terraform porque el backend no puede administrarse a sí mismo:
# Terraform necesita el bucket ANTES de poder guardar cualquier state.
# Es idempotente: si el bucket ya existe, no hace nada.
# Uso: ./scripts/bootstrap-backend.sh
# =============================================================================
set -euo pipefail

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="todo-api-tfstate-${ACCOUNT_ID}"   # Account ID = nombre único global

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "El bucket $BUCKET ya existe."
else
  echo "Creando bucket $BUCKET..."
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
fi

# Versionado: permite recuperar un state anterior si algo se corrompe
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# Cifrado en reposo por defecto
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Bloquear todo acceso público (el state tiene secretos)
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo ""
echo "Listo. Bucket del backend: $BUCKET"
echo "Siguiente: cd terraform && terraform init -reconfigure -backend-config=\"bucket=$BUCKET\""
