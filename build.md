Implementa en Godot una aplicación de escritorio que funcione como **UI visual para gestionar múltiples agentes de OpenCode CLI**.

Objetivo: crear agentes visualmente, asignarles modelo, skills, personalidad y personaje, y utilizarlos para trabajar sobre proyectos reales mediante OpenCode CLI.

## 1. Arquitectura

Godot será únicamente el frontend/orquestador visual.

OpenCode CLI será el backend de ejecución y manejará:

* LLM
* tools
* filesystem
* Git
* ejecución de comandos
* contexto
* sesiones
* agentes/skills de OpenCode

La comunicación debe permitir lanzar procesos de OpenCode, enviar tareas y recibir su output/eventos en tiempo real.

No implementar un LLM propio ni recrear las herramientas de OpenCode.

## 2. UI principal

Crear una interfaz dividida en:

### Panel izquierdo — Agents

Lista de agentes disponibles.

Cada agente debe mostrar:

* Avatar/personaje
* Nombre
* Estado
* Modelo
* Indicador visual de actividad

Permitir:

* Crear agente
* Editar agente
* Eliminar agente
* Seleccionar agente
* Iniciar/detener agente

### Panel central — Workspace

Mostrar el proyecto actualmente seleccionado y la actividad del agente.

Incluir:

* Proyecto/directorio de trabajo
* Tarea actual
* Archivos modificados
* Git status
* Output/log de OpenCode
* Controles Start / Stop

### Panel derecho — Team Chat

Crear un chat persistente donde puedan participar:

* Usuario
* Todos los agentes
* Agentes específicos

Soportar:

* mensajes del usuario
* respuestas de agentes
* `@AgentName`
* `@all`
* timestamps
* indicador de agente escribiendo/trabajando

Los agentes deben poder recibir mensajes relevantes del chat y responder dentro del mismo thread.

## 3. Agent Editor

Crear una pantalla para configurar agentes.

Campos:

* Name
* Model
* System prompt/personality
* Skills
* Project/workspace
* Character

Ejemplo:

```text
Name: Godot Coder
Model: provider/model
Skills:
  Godot
  GDScript
  Debugging
  Git
```

Los agentes deben guardarse persistentemente como perfiles.

Cuando un agente sea llamado posteriormente, cargar automáticamente su configuración y skills.

Permitir agregar skills temporales durante una sesión sin modificar permanentemente el perfil.

## 4. Character System

Cada agente puede tener su propio personaje.

Usar inicialmente:

```text
images/agent1/agent.png
```

como imagen de prueba para **todas las animaciones**.

No crear assets nuevos todavía.

Todos los frames deben utilizar un tamaño estándar de:

```text
256x256 px
```

El número de frames por animación queda libre.

Permitir posteriormente importar spritesheets/frames personalizados desde la UI.

## 5. Animation States

Implementar estos estados:

```text
idle
thinking
working
reading
coding
terminal
searching
waiting
question
approval
error
success
offline
```

Mapear eventos/acciones de OpenCode a estos estados.

Ejemplo:

```text
read       → reading
edit       → coding
bash       → terminal
grep       → searching
question   → question
permission → approval
completed  → success
error      → error
```

Permitir fallback entre estados.

Ejemplo:

```text
coding     → working
terminal   → working
reading    → thinking
searching  → thinking
```

Por ahora, todas las animaciones pueden utilizar `agent.png` como placeholder.

La arquitectura debe permitir reemplazar posteriormente cada estado por una animación personalizada desde la UI.

## 6. Agent Runtime

Crear un sistema `AgentManager` encargado de:

* cargar perfiles
* iniciar agentes
* detener agentes
* mantener sesiones
* asignar proyectos
* enviar prompts
* recibir output
* convertir eventos de OpenCode en estados visuales
* publicar mensajes de agentes en Team Chat

Cada agente debe poder mantener su propia sesión de OpenCode.

Evitar crear innecesariamente una sesión nueva cada vez que se envía un mensaje.

## 7. Persistencia

Guardar agentes localmente.

Separar claramente:

```text
Agent Profile
├── name
├── model
├── personality/system prompt
├── skills
├── character
├── animations
└── OpenCode configuration
```

y:

```text
Session
├── agent
├── project
├── OpenCode session ID
├── current task
└── runtime state
```

## 8. Preparar para multi-agent

La arquitectura debe permitir posteriormente:

```text
Manager
├── Coder
├── QA
├── Designer
└── Documentation
```

Los agentes deben poder comunicarse mediante el Team Chat y recibir tareas individuales.

No implementar un complejo sistema de orchestration todavía; dejar interfaces/clases preparadas para añadirlo posteriormente.

## 9. UX

Priorizar una interfaz visual limpia y rápida.

Los personajes deben ser parte importante de la experiencia.

El usuario debe poder ver inmediatamente:

```text
👨‍💻 Coder       🟢 Coding
🧪 QA           🟡 Thinking
🎨 Designer     ⚪ Idle
```

y observar visualmente qué está haciendo cada agente.

## 10. Implementación por fases

Implementar en este orden:

1. Crear estructura base del proyecto.
2. Crear layout principal de tres paneles.
3. Implementar Agent Profiles.
4. Implementar Agent Editor.
5. Implementar sistema de personajes.
6. Implementar estados y animaciones.
7. Implementar Team Chat.
8. Implementar ejecución de OpenCode CLI.
9. Implementar sesiones persistentes.
10. Implementar recepción de eventos/output.
11. Conectar eventos con estados de animación.
12. Integrar agentes con Team Chat.
13. Probar múltiples agentes.
14. Pulir UX y manejo de errores.

No sobrearquitecturar.

Primero conseguir un flujo funcional:

```text
Create Agent
→ Configure Model + Skills
→ Save
→ Select Project
→ Start Agent
→ Send Task
→ OpenCode trabaja
→ Godot muestra actividad
→ Agent responde en Team Chat
→ Task complete
→ success animation
```

Usar `images/agent1/agent.png` como placeholder visual durante toda esta primera implementación.
