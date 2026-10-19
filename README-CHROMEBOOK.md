# Instalación en Chromebook (Crostini / Linux)

Guía paso a paso para correr Santuario (edición Chromebook) dentro del contenedor Linux de ChromeOS.

## 0. Requisitos

- Un Chromebook con **Linux (Crostini)** activado. Si no lo tienes activado: `Configuración` → `Avanzada` →
  `Desarrolladores` → `Linux` → `Activar`. ChromeOS crea un contenedor Debian y una terminal de "Linux".
- Al menos **4 GB de RAM libres** para los modelos más pequeños (más si quieres usar las regiones grandes como
  `hermes`, `analyst` o `libre8`; mira la tabla de RAM en el [README](README.md)).
- Espacio en disco: cada modelo pesa entre ~1 y ~5 GB. Si tu Chromebook tiene poco espacio, puedes ampliar el disco
  asignado a Linux en `Configuración` → `Linux` → `Espacio en disco`.

## 1. Preparar el contenedor Linux

Abre la app "Terminal" (Linux) y actualiza los paquetes:

```bash
sudo apt update
sudo apt install -y curl jq git
```

- `curl` habla con la API de Ollama.
- `jq` lee y escribe el JSON de `brain.json` y de las respuestas de Ollama.
- `git` para clonar este repositorio.

## 2. Instalar Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Esto instala Ollama y, en la mayoría de los casos, lo registra como servicio (`systemctl --user status ollama` o
`systemctl status ollama`). Si no arranca solo, levántalo a mano en una terminal aparte y déjalo corriendo:

```bash
ollama serve
```

Comprueba que responde:

```bash
curl -s http://127.0.0.1:11434/api/tags
```

## 3. Clonar este repositorio

```bash
git clone https://github.com/ale65432/Santuario-Chromebook.git
cd Santuario-Chromebook
chmod +x bin/*.sh
```

## 4. Construir el cerebro

Con Ollama activo y conexión a internet (para descargar los modelos base la primera vez):

```bash
bin/instalar-cerebro.sh --pull
```

Esto lee `brain.json`, descarga (`ollama pull`) los modelos base que falten, y crea un modelo `santuario-<región>`
por cada región con su propio `Modelfile` (parámetros + instrucción de sistema). Si vuelves a ejecutar el script más
tarde sin `--pull`, solo reconstruye los modelos a partir de lo que ya tengas descargado — útil si editas
`brain.json` (por ejemplo, para quitar regiones y ahorrar espacio/RAM en un Chromebook con menos recursos).

Si tu Chromebook tiene poca RAM, puedes editar `brain.json` y quitar las regiones más pesadas (`hermes`, `analyst`,
`libre8`) antes de instalar; el enrutador sigue funcionando con las que queden, usando sus `fallback`.

## 5. Chatear

```bash
bin/santuario.sh
```

Verás la lista de regiones (`/cerebro`) y podrás escribir directamente. Comandos útiles dentro del chat:

- `/cerebro` — muestra las regiones instaladas y la RAM libre.
- `/auto` — modo automático (por defecto): cada mensaje se enruta según su contenido.
- `/code`, `/libre`, `/analyst`, etc. — fija una región concreta hasta el próximo `/auto`.
- `/reset` — borra el historial de la sesión actual (no afecta a `logs/`).
- `/bye` — sale del chat.

## Notas específicas de Chromebook

- **Rendimiento**: los Chromebooks suelen tener CPUs modestas (ARM o x86 de bajo consumo) y poca RAM. Prioriza las
  regiones ligeras (`general`, `code`, `agent`, `libre2`) y evita las de 5+ GB salvo que tu equipo tenga RAM de
  sobra; el router ya hace esta elección automáticamente según `min_free_ram_gb` y la RAM disponible.
- **El contenedor Linux comparte RAM con ChromeOS**: cierra pestañas/apps de Chrome pesadas antes de usar una región
  grande, o la descarga del modelo puede fallar o hacer swap.
- **Persistencia**: todo lo que clones y generes (modelos de Ollama, `logs/`, `modelfiles/*.Modelfile` generados)
  vive dentro del contenedor Linux de Crostini. Si borras el contenedor de Linux desde `Configuración`, se pierde
  todo; conviene respaldar `logs/` si te importa el historial.
- **Sin "manos" ni automatización de sistema**: esta edición es solo de chat. No abre pestañas de Chrome, no
  controla el teclado ni archivos del Chromebook — eso evita permisos invasivos en ChromeOS y mantiene el sandbox de
  Crostini intacto.
- **Actualizar**: `git pull` en la carpeta del repo trae cambios de `brain.json` o de los scripts; vuelve a correr
  `bin/instalar-cerebro.sh` (sin `--pull` si no cambiaron los modelos base) para regenerar los `Modelfile`.

## Solución de problemas

| Problema | Causa probable | Solución |
|---|---|---|
| `No se pudo contactar a Ollama` | El servicio no está corriendo | `ollama serve` en una terminal, o `systemctl --user start ollama` |
| `El cerebro no esta instalado` | Nunca corriste el instalador | `bin/instalar-cerebro.sh --pull` |
| Se queda "cargando región" mucho tiempo | RAM insuficiente / primera carga del modelo | Cierra apps de Chrome, prueba con una región más ligera (`/general`, `/code`) |
| `Falta 'jq'` o `Falta 'curl'` | Paquetes no instalados | `sudo apt install -y curl jq` |
