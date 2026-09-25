#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Slay · script de desarrollo
# Ejecuta la app con las claves de Supabase leídas de .env
# Uso:  ./run.sh linux | android | windows
#
# Antes de correr, copiá .env.example a .env y completá los valores.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"

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

# Si se especificó 'android', detectar automáticamente el ID del dispositivo conectado
if [ "$DEVICE" = "android" ]; then
  ANDROID_ID=""
  if command -v adb >/dev/null 2>&1; then
    ANDROID_ID=$(adb devices | awk '$2=="device"{print $1}' | head -n 1 || true)
  fi
  if [ -z "$ANDROID_ID" ] && command -v flutter >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    ANDROID_ID=$(flutter devices --machine 2>/dev/null | python3 -c "import sys, json; devs = json.load(sys.stdin); androids = [d['id'] for d in devs if 'android' in d.get('targetPlatform', '')]; print(androids[0] if androids else '')" 2>/dev/null || true)
  fi

  if [ -n "$ANDROID_ID" ]; then
    echo "📱 Dispositivo Android detectado: $ANDROID_ID"
    DEVICE="$ANDROID_ID"
  else
    echo "⚠️  No se detectó ningún dispositivo Android conectado vía adb/flutter."
  fi
fi

echo "▶ Ejecutando Slay en $DEVICE"
echo "  URL: $SUPABASE_URL"

flutter run -d "$DEVICE" \
  --android-skip-build-dependency-validation \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  "${@:2}"
