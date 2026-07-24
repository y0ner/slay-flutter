#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Slay · script de desarrollo
# Ejecuta la app con las claves de Supabase leídas de .env
# Uso:  ./run.sh linux | android | windows
#
# Antes de correr, copiá .env.example a .env y completá los valores.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

export PATH="$HOME/flutter/bin:$PATH"

if [ ! -f .env ]; then
  echo "❌ No se encontró .env"
  echo "   cp .env.example .env  y completá los valores"
  exit 1
fi

# shellcheck disable=SC1091
set -a
source .env
set +a

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "❌ .env debe definir SUPABASE_URL y SUPABASE_ANON_KEY"
  exit 1
fi

DEVICE="${1:-linux}"

echo "▶ Ejecutando Slay en $DEVICE"
echo "  URL: $SUPABASE_URL"

flutter run -d "$DEVICE" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
