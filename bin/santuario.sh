#!/usr/bin/env bash
# Santuario (edicion Chromebook) - enrutador del cerebro, solo chat. Puerto bash+curl+jq, sin dependencias de Windows.
# Lee las regiones de brain.json, elige la region segun el texto y la RAM libre, y habla con Ollama en 127.0.0.1:11434.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$HERE/lib.sh"

for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Falta '$cmd'. Instalalo (sudo apt install -y $cmd) y vuelve a intentarlo." >&2; exit 1; }
done

LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

DEFAULT_ID=$(brain_default_id)
MODE="auto"
LOADED_MODEL=""
LOADED_RAM="0"
AVAIL_EXTRA="0"
MAX_MSGS=12
MAX_CHARS=8000

declare -a HIST_ROLE=()
declare -a HIST_CONTENT=()

hist_add() { HIST_ROLE+=("$1"); HIST_CONTENT+=("$2"); }
hist_clear() { HIST_ROLE=(); HIST_CONTENT=(); }
hist_trim() {
  while [ "${#HIST_ROLE[@]}" -gt "$MAX_MSGS" ]; do
    HIST_ROLE=("${HIST_ROLE[@]:1}"); HIST_CONTENT=("${HIST_CONTENT[@]:1}")
  done
  local chars=0 i
  for c in "${HIST_CONTENT[@]}"; do chars=$((chars + ${#c})); done
  while [ "${#HIST_ROLE[@]}" -gt 1 ] && [ "$chars" -gt "$MAX_CHARS" ]; do
    chars=$((chars - ${#HIST_CONTENT[0]}))
    HIST_ROLE=("${HIST_ROLE[@]:1}"); HIST_CONTENT=("${HIST_CONTENT[@]:1}")
  done
}
hist_json() {
  local i n=${#HIST_ROLE[@]} out="[]"
  for ((i = 0; i < n; i++)); do
    out=$(jq -c --argjson arr "$out" --arg role "${HIST_ROLE[$i]}" --arg content "${HIST_CONTENT[$i]}" \
      '$arr + [{role:$role, content:$content}]' <<< '{}')
  done
  echo "$out"
}

show_brain() {
  echo ""
  echo "  Cerebro de Santuario   (RAM: $(mem_total_gb) GB total, $(mem_avail_gb) GB libres)"
  INSTALLED=$(get_installed)
  local ids; ids=$(brain_region_ids)
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    local model base_name label ram_gb st
    model=$(region_field "$id" model); base_name=$(region_field "$id" base_name)
    label=$(region_field "$id" label); ram_gb=$(region_field "$id" ram_gb)
    if is_installed "$model" "$INSTALLED"; then st="ok   "; else st="FALTA"; fi
    printf "  [%s] /%-13s %-27s %-30s ~%s GB\n" "$st" "$id" "$label" "$base_name" "$ram_gb"
  done <<< "$ids"
  echo ""
}

# Envia la conversacion a Ollama (streaming) e imprime la respuesta a medida que llega. Devuelve el texto completo en $CHAT_REPLY.
chat() {
  local model="$1" messages="$2"
  local payload; payload=$(jq -cn --arg m "$model" --argjson msgs "$messages" '{model:$m, messages:$msgs, stream:true, think:false}')
  local full="" line content done_flag eval_count eval_duration
  full=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    content=$(printf '%s' "$line" | jq -r '.message.content // ""' 2>/dev/null) || continue
    if [ -n "$content" ]; then printf '%s' "$content"; full+="$content"; fi
    done_flag=$(printf '%s' "$line" | jq -r '.done // false' 2>/dev/null)
    if [ "$done_flag" = "true" ]; then
      eval_count=$(printf '%s' "$line" | jq -r '.eval_count // 0')
      eval_duration=$(printf '%s' "$line" | jq -r '.eval_duration // 0')
    fi
  done < <(curl -s -N -m 1800 -X POST "$BASE/api/chat" -H 'Content-Type: application/json' -d "$payload")
  echo ""
  if [ -n "${eval_duration:-}" ] && [ "${eval_duration:-0}" -gt 0 ] 2>/dev/null; then
    local tps; tps=$(awk -v c="$eval_count" -v d="$eval_duration" 'BEGIN { printf "%.1f", c/(d/1e9) }')
    echo "  [$eval_count tokens, $tps tok/s]"
  fi
  CHAT_REPLY="$full"
}

echo ""
echo "  iniciando el cerebro (Ollama)..."
if ! wait_ollama; then
  echo "  No se pudo contactar a Ollama en $BASE."
  echo "  Arrancalo con: ollama serve   (o systemctl --user start ollama / systemctl start ollama)"
  exit 1
fi
INSTALLED=$(get_installed)
DEFAULT_MODEL=$(region_field "$DEFAULT_ID" model)
if ! is_installed "$DEFAULT_MODEL" "$INSTALLED"; then
  echo "  El cerebro no esta instalado. Ejecuta: bin/instalar-cerebro.sh --pull"
  show_brain
  exit 1
fi

echo ""
echo "  S A N T U A R I O   (edicion Chromebook)"
echo "  Tu cerebro local. Cada solicitud va a la region adecuada. Solo chat: sin manos ni acceso al sistema."
show_brain
echo "  Comandos: /cerebro  /auto  /<region>  /reset  /bye"
echo "  Auto: si una region con filtros se niega a responder, reintenta con la region libre."
echo ""

while true; do
  printf 'tu> '
  IFS= read -r q || { echo ""; break; }
  [ -z "${q// /}" ] && continue
  t=$(normalize "$q")
  t="${t#"${t%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"  # trim

  case "$t" in
    "/bye"|"/exit"|"/salir") break ;;
    "/reset") hist_clear; echo "  (historial borrado)"; continue ;;
    "/cerebro") show_brain; continue ;;
    "/auto") MODE="auto"; echo "  (modo: auto)"; continue ;;
  esac
  if [[ "$t" == /* ]]; then
    region_candidate="${t#/}"
    if printf '%s\n' "$(brain_region_ids)" | grep -qxF "$region_candidate"; then
      MODE="$region_candidate"; echo "  (modo fijo: $MODE)"; continue
    fi
    echo "  Comando desconocido. Usa /cerebro para ver las regiones."; continue
  fi

  if [ "$MODE" = "auto" ]; then want=$(pick_region "$q"); else want="$MODE"; fi
  region_id=$(resolve_region "$want")
  model=$(region_field "$region_id" model)
  label=$(region_field "$region_id" label)
  base_name=$(region_field "$region_id" base_name)
  ram_gb=$(region_field "$region_id" ram_gb)

  if [ "$LOADED_MODEL" != "$model" ]; then
    [ -n "$LOADED_MODEL" ] && unload_model "$LOADED_MODEL"
    note=""
    [ "$region_id" != "$want" ] && note=" (pedida: $want, ajustada por RAM/instalacion)"
    echo "  -> $label [$base_name]$note"
    echo "  (cargando region, la primera vez tarda)"
  fi
  LOADED_MODEL="$model"; LOADED_RAM="$ram_gb"; AVAIL_EXTRA="$LOADED_RAM"

  hist_add "user" "$q"
  hist_trim
  messages=$(hist_json)
  chat "$model" "$messages"
  answer="$CHAT_REPLY"

  if [ "$MODE" = "auto" ] && ! printf ' %s ' "$LIBRE_FAMILY" | grep -q " $region_id "; then
    norm_answer=$(normalize "$answer")
    if printf '%s' "$norm_answer" | grep -Eiq "$REFUSAL_RX"; then
      libre_id=$(resolve_region "libre")
      libre_model=$(region_field "$libre_id" model)
      libre_label=$(region_field "$libre_id" label)
      libre_base=$(region_field "$libre_id" base_name)
      echo "  -> rechazo detectado, reintentando con: $libre_label [$libre_base]"
      if [ "$LOADED_MODEL" != "$libre_model" ]; then
        unload_model "$LOADED_MODEL"
        echo "  (cargando region, la primera vez tarda)"
      fi
      LOADED_MODEL="$libre_model"; LOADED_RAM=$(region_field "$libre_id" ram_gb); AVAIL_EXTRA="$LOADED_RAM"
      chat "$libre_model" "$messages"
      answer="$CHAT_REPLY"
      region_id="$libre_id"
    fi
  fi

  hist_add "assistant" "$answer"
  hist_trim

  log_file="$LOG_DIR/chat-$(date +%Y-%m-%d).txt"
  {
    printf '[%s] tu: %s\n' "$(date +%H:%M:%S)" "$q"
    printf '[%s] santuario (%s): %s\n\n' "$(date +%H:%M:%S)" "$region_id" "$answer"
  } | redact_secrets >> "$log_file"

  echo ""
done

[ -n "$LOADED_MODEL" ] && unload_model "$LOADED_MODEL"
