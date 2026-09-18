# my-agents-team

Aplicación de escritorio en Godot 4 que funciona como interfaz visual para gestionar y supervisar un equipo de agentes de IA basados en **OpenCode CLI**. Cada agente trabaja en su propio proyecto/task, muestra su estado con un personaje animado y se comunica contigo y con los demás agentes a través de un chat de equipo.

## Características

- **Gestión de agentes**: crea, edita, duplica y elimina agentes con nombre, modelo (catálogo de OpenCode), variante, agente de OpenCode, proyecto y skills.
- **Espacio de trabajo por agente**: ruta del proyecto, tarea actual, botón Start/Stop, vista de personaje con animaciones según el estado (thinking, coding, terminal, searching, etc.), archivos modificados y estado de Git en vivo.
- **Output log en tiempo real**: proceso de razonamiento (`[think]`), uso de herramientas (`[tool]`), errores de OpenCode con su mensaje real, y salida de stderr separada de las respuestas.
- **Team Chat**: envía tareas a uno o varios agentes con `@Agente` o `@all`, indicador de "escribiendo...", filtro por agente, e indicadores de tokens/coste/contexto por agente. Click derecho sobre un mensaje para copiarlo.
- **Permisos y preguntas**: si un agente pide permiso o hace una pregunta, aparece un popup con su avatar, el detalle y las opciones (Allow once/Always allow/Reject, o las respuestas disponibles con opción de escribir la tuya).
- **Sesiones de OpenCode**: cada agente reutiliza su session ID para mantener contexto; al hacer click derecho sobre un agente puedes crear sesión nueva, archivar, borrar o volver a sesiones anteriores.
- **Modelo/variante en caliente**: cambia de modelo o variante desde el menú contextual del agente sin editar su perfil.
- **Colaboración entre agentes**: cada agente recibe contexto de sus compañeros y puede delegar tareas mencionándolos en su respuesta. Las menciones entre agentes se entregan como nuevas tareas, con identificación del remitente y límites para evitar cadenas repetitivas.
- **Cola de mensajes**: si un agente está ocupado, los mensajes del usuario y de sus compañeros quedan pendientes y se entregan cuando termina.
- **Respuesta rápida en el chat**: el menú contextual de un mensaje de agente permite insertar su mención para responderle.
- **Organización visual por proyecto**: las tarjetas muestran la carpeta del proyecto y permiten asignar un color compartido por los agentes que trabajan en él.
- **Nombres de sesión personalizados**: renombra sesiones localmente desde el menú del agente para identificarlas con facilidad.
- **Skills temporales**: añade skills a la sesión desde el Workspace, con opción de quitarlas individualmente o limpiar la lista.
- **Ajustes del sistema (Sis)**: activa o desactiva sonidos, cambia la interfaz entre inglés y español y elige los temas `light`, `soft` o `dark`. También puedes indicar el idioma de respuesta de los agentes y tu nombre, que se incorporan a sus instrucciones.
- **Remote Chat privado**: abre Team Chat desde teléfono o navegador mediante una PWA local, autenticada con token y publicada de forma privada con Tailscale Serve; muestra estados y avatar idle de agentes, filtro y respuesta directa.
- **Interfaz adaptable**: paneles y diálogos ajustados al tamaño de la ventana, texto nítido al redimensionar y sonidos de notificación del chat.

## Requisitos

- [Godot 4.7](https://godotengine.org/download) (proyecto Forward Plus; sin addons ni plugins externos)
- [`opencode` CLI](https://github.com/sst/opencode) disponible en el `PATH`, ya configurada con tus proveedores/modelos
- Git instalado (para el estado de repositorio por proyecto; opcional)
- [Tailscale](https://tailscale.com/download) instalado e iniciado en el PC y dispositivo remoto (solo para Remote Chat)
- [`qrencode`](https://fukuchi.org/works/qrencode/) opcional, para abrir en el teléfono la URL y token mediante **Show QR** desde Sis

## Instalación y ejecución

```bash
git clone https://github.com/geraldb1996/my-agents.git my-agents-team
cd my-agents-team
godot --path . scenes/main/main.tscn
```

También puedes abrir el proyecto con el editor de Godot (`import` de `project.godot`) y ejecutar la escena `scenes/main/main.tscn`.

## Uso

1. **Crea un agente** con el botón *New* del panel izquierdo: nombre, modelo, proyecto (carpeta de trabajo) y skills.
2. **Selecciónalo** para ver su espacio de trabajo (personaje, archivos, Git, output).
3. **Asigna una tarea** desde el Workspace o desde el Team Chat (usa `@Nombre` para dirigirte a un agente o `@all` para todo el equipo).
4. El agente trabaja a través de un `opencode serve` gestionado por la app (eventos en vivo por SSE), su personaje anima el estado y el resultado final llega al Team Chat.
5. Click derecho sobre un agente para gestionar o renombrar sesiones, cambiar modelo/variante, asignar color al proyecto, editar, duplicar o borrar; click derecho sobre un mensaje del chat para copiarlo o responder al agente con una mención.
6. Si el agente está ocupado, puedes seguir enviándole mensajes: se pondrán en cola. Los agentes también pueden enviarse tareas mediante menciones; para nombres con espacios, usa guiones bajos, por ejemplo `@Mi_Agente`.
7. Abre **Sis** para personalizar sonidos, idioma y tema de la interfaz, tu nombre y el idioma de respuesta de los agentes.

## Remote Chat con Tailscale

Remote Chat no abre puertos de red local ni de Internet. La aplicación escucha solo en `127.0.0.1`; Tailscale Serve proporciona una URL HTTPS privada para dispositivos de tu misma tailnet.

### Configurar una vez

1. Instala Tailscale e inicia sesión con la misma cuenta o tailnet en el PC donde ejecutas MyAgents y en el teléfono.
2. En MyAgents abre la pestaña **Sis**.
3. En la sección **Remote Chat**, activa **Enable Remote Chat**, conserva el puerto `38471` o elige otro libre, y pulsa **Save**.
4. En una terminal del PC ejecuta:

   ```bash
   tailscale serve --bg 38471
   ```

5. Obtén la URL privada:

   ```bash
   tailscale serve status
   ```

   El resultado mostrará una dirección similar a `https://mi-pc.mi-tailnet.ts.net`. Esa es la URL que debes abrir desde el teléfono, no `127.0.0.1` ni la IP `192.168.x.x` del PC.
6. En **Sis**, pulsa **Copy Token**. En la PWA abierta en el teléfono, pega el token y conéctate. La URL base se completa automáticamente; si no, pega la URL HTTPS obtenida en el paso anterior.
7. Opcionalmente, pega esa URL HTTPS en **Phone access URL**, guarda y pulsa **Show QR**. Si `qrencode` está instalado, la aplicación abre un QR local con URL y token para escanear desde el teléfono.

La PWA permite leer y enviar mensajes de Team Chat, ver estados y responder solicitudes pendientes de agentes. Los permisos ofrecen únicamente **Allow once**, **Always allow** (cuando OpenCode lo admite) y **Reject**; las preguntas conservan sus opciones y respuesta personalizada. No permite introducir comandos, explorar archivos, ver perfiles ni acceder directamente a OpenCode. Aprobar un permiso sí autoriza al agente a ejecutar la acción mostrada, por lo que debes revisar comando, ruta y patrones antes de aceptarlo.

### Uso diario

1. Inicia MyAgents y asegúrate de que Remote Chat sigue activado en **Sis**.
2. Abre la URL HTTPS de Tailscale desde el teléfono.
3. Introduce el token si el navegador no conserva la sesión actual.

### Seguridad y solución de problemas

- No uses `tailscale funnel`, reenvío de puertos del router ni un listener `0.0.0.0`: harían accesible el servicio fuera de tu tailnet.
- Si `tailscale serve status` muestra `No serve config`, repite `tailscale serve --bg 38471` usando el puerto configurado en **Sis**.
- Si el navegador no carga la PWA local, confirma que MyAgents está abierto, Remote Chat está activado y usa `http://127.0.0.1:38471/` desde el mismo PC.
- Si pierdes un teléfono o token, pulsa **Regenerate Token** en **Sis**. El token anterior queda invalidado inmediatamente.
- Para dejar de publicar el servicio, ejecuta:

  ```bash
  tailscale serve reset
  ```

  También puedes desactivar **Enable Remote Chat** y guardar desde **Sis**.

## Arquitectura

- **Godot** actúa solo como orquestador visual: no reimplementa el LLM ni las herramientas.
- **OpenCode CLI** es el backend de ejecución: un `opencode serve` global (autoload `OpenCodeServer`) recibe prompts por HTTP y emite los eventos de cada sesión por SSE, con session ID persistida.
- Persistencia local: perfiles en `user://agents/`, sesiones en `user://sessions/`, historial en `user://chat.json`, colores por proyecto en `user://project_colors.json` y ajustes en `user://settings.cfg`.
- Comunicación entre capas mediante señales (`EventBus`). `AgentManager` coordina la ejecución, las colas de mensajes y la delegación entre agentes; `ProfileStore` gestiona la persistencia de perfiles y chat.
- `ModelCatalog` y `SkillCatalog` proporcionan los catálogos; `SystemSettings` y `ThemeManager` gestionan preferencias, idioma, sonidos y apariencia.

```text
agents/default/  → Perfiles iniciales del equipo
scripts/
├── autoload/    → Coordinación, persistencia, servidor, catálogos y ajustes
├── core/        → OpenCodeRunner y modelos de datos
└── ui/          → Paneles, chat, editor, personajes y diálogos
scenes/          → Escenas de Godot
translations/    → Traducción de la interfaz al español
tests/           → Escenas y scripts de pruebas
ui_snd/          → Sonidos de la interfaz
```

## Licencia

MIT © 2026 Gerald Glitch (Geraldb1996)
