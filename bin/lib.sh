#!/usr/bin/env bash
# Santuario (edicion Chromebook) - biblioteca comun del enrutador. La usan santuario.sh e instalar-cerebro.sh.
# Requiere: bash, curl, jq. Puerto de Ollama: 127.0.0.1:11434 (igual que la edicion de escritorio).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="http://127.0.0.1:11434"
BRAIN_FILE="$ROOT/brain.json"

if [ ! -f "$BRAIN_FILE" ]; then
  echo "No se encuentra $BRAIN_FILE" >&2
  exit 1
fi

# Rechazos tipicos de un modelo con filtros -> se reintenta con la region libre (mismo patron que la edicion de escritorio)
REFUSAL_RX='no puedo (ayudar|ayudarte|ayudarle|proporcionar|cumplir|asistir|responder|generar|crear|darte)|lo siento,? pero no|no estoy (en condiciones|autorizado|permitido)|no me es posible|como (asistente|modelo) (de ia|de inteligencia|de lenguaje),? no|i can.?t (help|assist|provide)|i.m sorry,? but'
LIBRE_FAMILY="libre libre8 libre2 gemma analyst analyst_lite"

brain_identity() { jq -r '.identity' "$BRAIN_FILE"; }
brain_default_id() { jq -r '[.regions[] | select(.default==true)][0].id' "$BRAIN_FILE"; }
brain_region_ids() { jq -r '.regions[].id' "$BRAIN_FILE"; }
region_field() { # region_field <id> <campo>
  jq -r --arg id "$1" --arg f "$2" '.regions[] | select(.id==$id) | .[$f]' "$BRAIN_FILE"
}
region_json() { jq -c --arg id "$1" '.regions[] | select(.id==$id)' "$BRAIN_FILE"; }

# Normaliza: minusculas y sin acentos (para comparar con los "triggers" de brain.json, igual que Normalize() en PowerShell)
normalize() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | \
    sed -e 's/[áàäâã]/a/g' -e 's/[éèëê]/e/g' -e 's/[íìïî]/i/g' -e 's/[óòöôõ]/o/g' -e 's/[úùüû]/u/g' -e 's/ñ/n/g'
}

mem_total_gb() {
  local kb
  kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  awk -v kb="$kb" 'BEGIN { printf "%.1f", kb/1024/1024 }'
}
mem_avail_gb() {
  local kb
  kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  awk -v kb="$kb" 'BEGIN { printf "%.1f", kb/1024/1024 }'
}

# Lista de modelos instalados en Ollama (uno por linea, sin el sufijo :latest)
get_installed() {
  curl -s -m 15 "$BASE/api/tags" 2>/dev/null | jq -r '.models[]?.name' 2>/dev/null | sed 's/:latest$//'
}
is_installed() { # is_installed <nombre> <<< "$INSTALLED"
  local name="$1" installed="$2"
  printf '%s\n' "$installed" | grep -qxF "$name"
}

wait_ollama() {
  local i
  for i in $(seq 1 60); do
    if curl -s -m 2 "$BASE/api/tags" >/dev/null 2>&1; then return 0; fi
    sleep 0.7
  done
  return 1
}

# Region final a usar: aplica mejora (upgrade_to) si hay RAM y respaldo (fallback) si falta el modelo o la RAM.
# Variables de entrada: INSTALLED (modelos instalados, uno por linea), AVAIL_EXTRA (GB ya contados como libres por descargar el modelo actual)
resolve_region() {
  local id="$1" depth="${2:-0}"
  if [ "$depth" -gt 6 ] || [ -z "$id" ] || [ "$id" = "null" ]; then
    brain_default_id; return
  fi
  local rj; rj=$(region_json "$id")
  if [ -z "$rj" ] || [ "$rj" = "null" ]; then brain_default_id; return; fi
  local free; free=$(awk -v a="$(mem_avail_gb)" -v e="$AVAIL_EXTRA" 'BEGIN { printf "%.2f", a+e }')
  local upgrade; upgrade=$(echo "$rj" | jq -r '.upgrade_to // ""')
  if [ -n "$upgrade" ]; then
    local up_model up_min
    up_model=$(region_field "$upgrade" model); up_min=$(region_field "$upgrade" min_free_ram_gb)
    if is_installed "$up_model" "$INSTALLED" && awk -v f="$free" -v m="$up_min" 'BEGIN{exit !(f>=m)}'; then
      echo "$upgrade"; return
    fi
  fi
  local model min; model=$(echo "$rj" | jq -r '.model'); min=$(echo "$rj" | jq -r '.min_free_ram_gb')
  if is_installed "$model" "$INSTALLED" && awk -v f="$free" -v m="$min" 'BEGIN{exit !(f>=m)}'; then
    echo "$id"; return
  fi
  local fallback; fallback=$(echo "$rj" | jq -r '.fallback // ""')
  if [ -n "$fallback" ]; then resolve_region "$fallback" $((depth + 1)); return; fi
  if is_installed "$model" "$INSTALLED"; then echo "$id"; return; fi
  brain_default_id
}

# Elige la region segun el texto (triggers), probando por prioridad ascendente, igual que Pick-Region en PowerShell.
pick_region() {
  local text="$1" n; n=$(normalize "$text")
  local ids; ids=$(jq -r '[.regions[] | select(.auto==true and (.triggers // "")!="")] | sort_by(.priority) | .[].id' "$BRAIN_FILE")
  local id rx
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    rx=$(region_field "$id" triggers)
    [ -z "$rx" ] && continue
    if printf '%s' "$n" | grep -Eiq "$rx"; then echo "$id"; return; fi
  done <<< "$ids"
  brain_default_id
}

unload_model() {
  local model="$1"
  [ -z "$model" ] && return
  curl -s -m 30 -X POST "$BASE/api/generate" -H 'Content-Type: application/json' \
    -d "$(jq -cn --arg m "$model" '{model:$m, keep_alive:0}')" >/dev/null 2>&1
}

# Quita secretos evidentes antes de guardarlos en el registro (mismo patron que Redact-Secrets en la edicion de escritorio)
redact_secrets() {
  sed -E \
    -e 's/bot[0-9]{5,}:[A-Za-z0-9_-]{20,}/bot[REDACTADO]/g' \
    -e 's/[0-9]{6,}:[A-Za-z0-9_-]{30,}/[TOKEN]/g' \
    -e 's/\b(AKIA|ASIA)[A-Z0-9]{16}\b/[AWS-KEY]/g' \
    -e 's/\bgh[pousr]_[A-Za-z0-9]{30,}\b/[GITHUB-TOKEN]/g' \
    -e 's/\bxox[abprs]-[A-Za-z0-9-]{10,}/[SLACK-TOKEN]/g' \
    -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[CLAVE-PRIVADA]/g' \
    -e 's/(password|passwd|pwd|contrasena|secret|api_?key|token)([[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1\2[OCULTO]/gi'
}
