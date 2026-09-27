# MyAgents User Guide

Welcome to MyAgents, a desktop workspace for managing a small team of AI agents powered by OpenCode. Each agent can work in its own project, keep a separate session, report its progress, and collaborate with other agents through Team Chat.

## Before You Start

You need:

- Godot 4.7.
- OpenCode CLI installed, available in your `PATH`, and configured with your providers and models.
- Git if you want project repository status inside the app.
- Tailscale on your computer and phone if you want to use Remote Chat.

Start the application from the project directory:

```bash
godot --path . scenes/main/main.tscn
```

You can also import `project.godot` in the Godot editor and run the main scene.

## Meet The Workspace

The application has three main areas:

- **Agents panel:** create agents, switch between them, and manage their settings or sessions.
- **Workspace:** assign work and inspect the selected agent's task, files, Git status, output, temporary skills, and system settings.
- **Team Chat:** talk to one agent or the whole team and follow their replies.

## Create Your First Agent

1. Select **+ New** in the Agents panel.
2. Enter a name for the agent.
3. Choose an OpenCode model and, if needed, a model variant.
4. Select the project folder where the agent should work.
5. Add personality instructions or permanent skills if desired.
6. Configure character animations, or keep the default placeholder.
7. Save the agent.

The project folder matters: an agent cannot start a task until it has a valid workspace.

## Send Work To An Agent

Select an agent and enter a task in the Workspace, or send a message through Team Chat.

In Team Chat:

- Use `@AgentName` to target one agent.
- Use underscores for names containing spaces, such as `@Code_Reviewer`.
- Use `@all` to send the message to every agent.
- If no mention is included, the currently selected agent receives the message.

If an agent is already working, new chat messages are queued and delivered when its current task finishes.

## Follow Agent Activity

The Workspace provides several useful tabs:

- **Task:** the current task assigned to the agent.
- **Files:** files read, created, modified, or deleted during the task.
- **Git:** branch and repository status for the selected project.
- **Output:** live reasoning, tool activity, errors, and execution details.
- **Sis:** global application and Remote Chat settings.

Agent cards display current state, context usage, token count, cost, and project information. You can also assign a color to a project so related agents are easier to recognize.

## Use Team Chat

Agent responses appear as chat messages while detailed tool activity remains in Output.

Useful chat actions:

- Right-click a message to copy it.
- Reply to an agent from its message to insert or select that agent as the recipient.
- Filter the chat to focus on one agent.
- Double-click a message to open a larger reading view.
- Use **Clear All** when you intentionally want to remove the complete chat history.

Agents can mention teammates in their replies. MyAgents delivers those mentions as new tasks, allowing the team to delegate work automatically.

## Handle Permissions And Questions

An agent may pause and ask for permission before using a tool or may ask you to choose between several options.

For permissions, review the command, path, or requested patterns before choosing:

- **Allow once:** approve only the current request.
- **Always allow:** approve the matching permission persistently when OpenCode offers this option.
- **Reject:** deny the request.

Questions may offer one choice, multiple choices, or a custom answer. The agent remains paused until you respond or reject the question.

These requests can be handled from both the desktop application and Remote Chat.

## Manage Sessions

Right-click an agent card to manage its OpenCode sessions:

- **New Session:** archive the current session and begin with fresh context.
- **Previous Sessions:** return to an earlier session.
- **Delete Session:** remove the active session without archiving it.
- **Rename Session:** give a session a clearer local name.

Changing language or user-name instructions only affects new sessions. Start a new session when you want an existing agent to receive updated initial instructions.

## Add Temporary Skills

Temporary skills add context only to the current session.

1. Select an agent.
2. Open the temporary skill controls in the Workspace.
3. Choose an installed global or project skill, load a Markdown/text file, or type custom instructions.
4. Remove individual entries or use **Clear** when they are no longer needed.

Temporary skills are cleared when you create, switch, or delete a session.

## Configure The Application

Open the **Sis** tab to configure:

- UI sounds.
- Light, Soft, or Dark theme.
- English or Spanish interface language.
- The language agents should use in new sessions.
- Your name, so agents can address you naturally.
- Remote Chat settings.

Select **Save** to apply changes. **Cancel** or Escape closes the dialog without applying the current draft.

## Set Up Remote Chat

Remote Chat lets you read Team Chat, send messages, select agents, view agent status, and answer permission or question requests from your phone.

The service listens only on `127.0.0.1`. This prevents other devices on your local network from connecting directly. Tailscale Serve provides the private HTTPS connection to your phone.

### One-Time Setup

1. Install Tailscale on the computer running MyAgents and on your phone.
2. Sign in to the same Tailscale account or tailnet on both devices.
3. In MyAgents, open **Sis**.
4. Enable **Remote Chat**.
5. Keep port `38471`, or choose another free port.
6. Select **Save**.
7. On the computer, run:

   ```bash
   tailscale serve --bg 38471
   ```

8. Display your private address:

   ```bash
   tailscale serve status
   ```

9. Open the displayed `https://...ts.net` address on your phone. Do not use the computer's `127.0.0.1` or `192.168.x.x` address from the phone.
10. In **Sis**, select **Copy Token** and enter that token in Remote Chat.

The token is kept in browser session storage, so you may need to enter it again after closing the browser session.

### Optional QR Setup

If `qrencode` is installed:

1. Paste the HTTPS Tailscale address into **Phone access URL** in Sis.
2. Save the settings.
3. Select **Show QR**.
4. Scan the generated QR code with your phone.

The QR contains the private address and access token. Treat it like a password and do not share screenshots of it.

### Stop Remote Access

Stop the Tailscale publication with:

```bash
tailscale serve reset
```

You can also disable Remote Chat from Sis. Use **Regenerate Token** if a device or token is lost; the previous token stops working immediately.

Never use Tailscale Funnel or router port forwarding for Remote Chat. The intended setup is private access inside your tailnet.

## Troubleshooting

### An Agent Does Not Start

- Confirm that the agent has a project folder.
- Confirm that OpenCode CLI is installed and configured.
- Check the agent's Output tab for the actual error.

### Remote Chat Does Not Open

- Keep MyAgents running.
- Confirm Remote Chat is enabled in Sis.
- Test `http://127.0.0.1:38471/` from the same computer.
- Run `tailscale serve status`. If it reports `No serve config`, run `tailscale serve --bg 38471` again.
- Make sure the phone is connected to the same tailnet.

### Remote Chat Looks Outdated

Close and reopen the Remote Chat page. The PWA caches application assets for installation and offline startup, but authenticated chat responses are never cached.

### The Agent Is Waiting Forever

Look for a permission or question card in the desktop application or under **Needs attention** in Remote Chat. The agent cannot continue until the request is answered.

## A Few Safety Tips

- Read permission details before approving them, especially commands and file paths.
- Use **Allow once** unless you intentionally want a persistent permission.
- Keep the Remote Chat token private.
- Regenerate the token after losing access to a device.
- Keep Remote Chat behind Tailscale rather than exposing it publicly.

Enjoy building with your team.
