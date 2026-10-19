#!/usr/bin/env bash
# Santuario (edicion Chromebook) - instala/reconstruye el cerebro: crea un modelo "santuario-*" por cada region de brain.json.
# Uso: bin/instalar-cerebro.sh [--pull]
#   --pull  descarga de internet los modelos base que falten (hf.co/... o el registro de Ollama). Sin --pull solo reconstruye con lo que ya tengas.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$HERE/lib.sh"

PULL=0
[ "${1:-}" = "--pull" ] && PULL=1

if ! command -v ollama >/dev/null 2>&1; then
  echo "No se encuentra el comando 'ollama'. Instalalo primero (ver README-CHROMEBOOK.md)." >&2
  exit 1
fi
if ! curl -s -m 5 "$BASE/api/tags" >/dev/null 2>&1; then
  echo "Ollama no esta activo en $BASE. Arrancalo con 'ollama serve' (o systemctl --user start ollama) y vuelve a intentarlo." >&2
  exit 1
fi

MODELFILES_DIR="$ROOT/modelfiles"
mkdir -p "$MODELFILES_DIR"

brain_text=$(jq -r '[.regions[].label] | map(ascii_downcase) | join(", ")' "$BRAIN_FILE")
identity=$(brain_identity)

ok=0
missing=()
total=$(jq '.regions | length' "$BRAIN_FILE")

ids=$(brain_region_ids)
while IFS= read -r id; do
  [ -z "$id" ] && continue
  rj=$(region_json "$id")
  model=$(echo "$rj" | jq -r '.model')
  alias_=$(echo "$rj" | jq -r '.alias')
  source_=$(echo "$rj" | jq -r '.source')
  base_name=$(echo "$rj" | jq -r '.base_name')
  label=$(echo "$rj" | jq -r '.label')
  role=$(echo "$rj" | jq -r '.role')
  temp=$(echo "$rj" | jq -r '.temperature')

  # El origen del modelo solo puede ser hf.co/<usuario>/<repo>:<etiqueta> o un nombre del registro de Ollama (mismo candado que la edicion de escritorio)
  if ! printf '%s' "$source_" | grep -Eq '^(hf\.co/[][:alnum:]._-]+/[][:alnum:]._-]+|[[:alnum:]._-]+(/[[:alnum:]._-]+)?):[[:alnum:]._-]+$'; then
    echo "[$id] origen de modelo no permitido en brain.json: $source_"
    missing+=("$id"); continue
  fi
  if printf '%s%s%s' "$identity" "$role" "$label" | grep -q '"""'; then
    echo "[$id] texto con comillas triples en brain.json: se rechaza"
    missing+=("$id"); continue
  fi

  printf '[%s] %s' "$id" "$base_name"
  INSTALLED=$(get_installed)
  if ! is_installed "$alias_" "$INSTALLED"; then
    if ! is_installed "$source_" "$INSTALLED"; then
      if [ "$PULL" = "1" ]; then
        printf ' - descargando...'
        if ! ollama pull "$source_" >/tmp/santuario-pull.log 2>&1; then
          echo " FALLO: $(tail -n1 /tmp/santuario-pull.log)"
          missing+=("$id"); continue
        fi
      else
        echo ' - FALTA (usa --pull para descargar)'
        missing+=("$id"); continue
      fi
    fi
    if ! ollama cp "$source_" "$alias_" >/tmp/santuario-cp.log 2>&1; then
      echo " FALLO cp: $(tail -n1 /tmp/santuario-cp.log)"
      missing+=("$id"); continue
    fi
  fi

  system=$(printf '%s' "$identity" | sed "s/{BRAIN}/${brain_text//\//\\/}/g; s/{REGION}/${label//\//\\/}/g")
  mf_path="$MODELFILES_DIR/$model.Modelfile"
  {
    echo "# Generado por instalar-cerebro.sh desde brain.json (region: $id). No editar a mano."
    echo "FROM $alias_"
    echo ""
    echo "PARAMETER num_ctx 4096"
    echo "PARAMETER temperature $temp"
    echo "PARAMETER top_p 0.9"
    echo "PARAMETER repeat_penalty 1.1"
    echo ""
    echo "SYSTEM \"\"\""
    printf '%s\n%s\n' "$system" "$role"
    echo "\"\"\""
  } > "$mf_path"

  if ollama create "$model" -f "$mf_path" >/tmp/santuario-create.log 2>&1; then
    echo ' -> OK'
    ok=$((ok + 1))
  else
    echo " FALLO create: $(tail -n1 /tmp/santuario-create.log)"
    missing+=("$id")
  fi
done <<< "$ids"

echo ""
echo "Regiones listas: $ok de $total"
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Pendientes: ${missing[*]}"
fi
