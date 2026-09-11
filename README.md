# my-agents-team

Aplicación de escritorio en Godot 4 que funciona como interfaz visual para gestionar y supervisar un equipo de agentes de IA basados en **OpenCode CLI**. Cada agente trabaja en su propio proyecto/task, muestra su estado con un personaje animado y se comunica contigo y con los demás agentes a través de un chat de equipo.

## Características

- **Gestión de agentes**: crea, edita y elimina agentes con nombre, modelo (catálogo de OpenCode), variante, agente de OpenCode, proyecto y skills.
- **Espacio de trabajo por agente**: ruta del proyecto, tarea actual, botón Start/Stop, vista de personaje con animaciones según el estado (thinking, coding, terminal, searching, etc.), archivos modificados y estado de Git en vivo.
- **Output log en tiempo real**: proceso de razonamiento (`[think]`), uso de herramientas (`[tool]`), errores de OpenCode con su mensaje real, y salida de stderr separada de las respuestas.
- **Team Chat**: envía tareas a uno o varios agentes con `@Agente` o `@all`, indicador de "escribiendo...", filtro por agente, e indicadores de tokens/coste/contexto por agente. Click derecho sobre un mensaje para copiarlo.
- **Sesiones de OpenCode**: cada agente reutiliza su session ID para mantener contexto; al hacer click derecho sobre un agente puedes crear sesión nueva, archivar, borrar o volver a sesiones anteriores.
- **Modelo/variante en caliente**: cambia de modelo o variante desde el menú contextual del agente sin editar su perfil.

## Requisitos

- [Godot 4.7](https://godotengine.org/download) (proyecto Forward Plus; sin addons ni plugins externos)
- [`opencode` CLI](https://github.com/sst/opencode) disponible en el `PATH`, ya configurada con tus proveedores/modelos
- Git instalado (para el estado de repositorio por proyecto; opcional)

## Instalación y ejecución

```bash
git clone https://github.com/geraldb1996/my-agents.git
cd my-agents-team
godot --path . scenes/main/main.tscn
```

También puedes abrir el proyecto con el editor de Godot (`import` de `project.godot`) y ejecutar la escena `scenes/main/main.tscn`.

## Uso

1. **Crea un agente** con el botón *New* del panel izquierdo: nombre, modelo, proyecto (carpeta de trabajo) y skills.
2. **Selecciónalo** para ver su espacio de trabajo (personaje, archivos, Git, output).
3. **Asigna una tarea** desde el Workspace o desde el Team Chat (usa `@Nombre` para dirigirte a un agente o `@all` para todo el equipo).
4. El agente lanza `opencode run --format json`, su personaje anima el estado en vivo y el resultado final llega al Team Chat.
5. Click derecho sobre un agente para sesiones, modelo/variante, edición o borrado; click derecho sobre un mensaje del chat para copiarlo.

## Arquitectura

- **Godot** actúa solo como orquestador visual: no reimplementa el LLM ni las herramientas.
- **OpenCode CLI** es el backend de ejecución: un proceso `opencode run --format json` por agente activo, con session ID persistida.
- Persistencia en JSON (`user://agents/`, `user://sessions/`): perfiles, sesiones e historial de chat.
- Comunicación entre capas mediante señales (`EventBus`); autoloads: `EventBus`, `ProfileStore`, `AgentManager`.

```
scripts/
├── autoload/   # EventBus, ProfileStore, AgentManager, catálogos
├── core/       # OpenCodeRunner (proceso CLI y parsing de eventos)
└── ui/         # Panels: agents, workspace, chat, editor, personaje
```

## Licencia

MIT © 2026 Gerald Glitch (Geraldb1996)
