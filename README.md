# Santuario — edición Chromebook

Asistente de IA local y privado, puerto **solo de chat** del proyecto Santuario para correr en el contenedor Linux
(Crostini) de un Chromebook, usando [Ollama](https://ollama.com) y bash.

Su "cerebro" son varios modelos pequeños (**regiones**); un enrutador (`bin/santuario.sh`) lee `brain.json`,
decide qué región responde cada mensaje según el texto y la RAM libre, y habla con Ollama en `127.0.0.1:11434`.
**Los modelos y Ollama no usan internet** durante el chat; el único momento en que se necesita red es para descargar
modelos nuevos con `bin/instalar-cerebro.sh --pull`.

> **Para instalar y arrancar paso a paso en un Chromebook, lee [README-CHROMEBOOK.md](README-CHROMEBOOK.md).**

## Qué trae esta edición (y qué no)

Esta es una versión **reducida a chat**, pensada para un Chromebook en vez de un USB de Windows:

- Sí: el enrutador de regiones, el chat por streaming, el registro de conversaciones en `logs/`, y el instalador
  de modelos (`bin/instalar-cerebro.sh`), igual que la edición de escritorio.
- No: nada específico de Windows. No se portó el control de Edge/navegador ("manos"), el agente 24/7, las tareas
  programadas, la integración con Telegram, el arranque automático con el sistema, ni la firma/verificación de
  integridad pensada para un USB. Si quieres esas funciones, usa la edición de escritorio del proyecto original.

## El cerebro (`brain.json`)

| Región | Modelo | RAM aprox. | Cuándo se usa |
|---|---|---|---|
| general | Qwen3.5 2B | 2.1 GB | por defecto, conversación en español |
| code | Qwen2.5-Coder 1.5B | 1.2 GB | programación y scripts |
| agent | Granite 4.0 1B | 1.1 GB | planes paso a paso, JSON de herramientas |
| hermes | Hermes 3 8B (Q3) | 5 GB | mejora de `agent` si hay >= 6.5 GB libres |
| analyst | Dolphin Mistral 7B | 5.5 GB | malware / logs / tráfico (análisis defensivo), >= 6.5 GB libres |
| analyst_lite | Dolphin Phi 2.7B | 2 GB | respaldo del analista con poca RAM |
| libre | Huihui Qwen3.5 4B abliterated | 3.5 GB | respuestas directas, sin filtros |
| libre8 | Llama 3.1 8B abliterated (Q3) | 5 GB | mejora de `libre` si hay RAM de sobra |
| libre2 | Huihui Qwen3.5 2B abliterated | 1.8 GB | respaldo de `libre` con poca RAM |
| gemma | Gemma 2 2B abliterated | 2.2 GB | voz alterna sin censura (licencia Gemma) |

Cada región define en `brain.json` su modelo base, la RAM mínima libre para usarla, una `upgrade_to` (región mejor si
hay RAM de sobra) y un `fallback` (región más ligera si falta el modelo o la RAM). El mismo `brain.json` es la única
fuente de verdad: tanto `bin/santuario.sh` como `bin/instalar-cerebro.sh` lo leen directamente, así que para ajustar
modelos o reglas de enrutado solo hay que editar ese archivo.

## Uso rápido

```bash
bin/instalar-cerebro.sh --pull   # primera vez: descarga y construye las regiones (necesita internet e Ollama activo)
bin/santuario.sh                 # chat
```

Comandos dentro del chat: `/cerebro` (ver regiones y RAM) · `/auto` · `/<region>` (fija una región, ej. `/code`,
`/libre`, `/analyst`) · `/reset` (borra el historial de la sesión) · `/bye` (salir).

Si una región con filtros se niega a responder, Santuario reintenta automáticamente con la región libre.
Cada conversación se guarda en `logs/chat-AAAA-MM-DD.txt` con los secretos evidentes (tokens, claves, contraseñas)
tapados antes de escribirlos a disco.

## Privacidad

- El chat solo habla con Ollama en `127.0.0.1:11434`; ningún mensaje sale a internet.
- La única operación con red es `bin/instalar-cerebro.sh --pull`, que descarga los modelos base que falten.
- Las conversaciones quedan solo en `logs/` de esta copia (en `.gitignore`, nunca se suben a git).

## Licencia y origen

Esta es una copia pública y reempaquetada, con el mismo nombre y marca **Santuario**, derivada del proyecto
Santuario original (`ale65432/Santuario`), reducida a un puerto de solo-chat para bash + Ollama en Chromebook/Linux.
