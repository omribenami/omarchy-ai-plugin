# Omarchy-AI

**Omarchy-AI** is a self-hosted, voice-driven **agentic assistant** for
[Omarchy](https://omarchy.org), the Arch-based Hyprland desktop. You say what
you want done, from the desk, from your phone, or from the TV across the
room. It plans the work, does it with real tools on your machine, checks the
result itself, and tells you when it is verified. It is not a chatbot bolted
onto a terminal.

Project home: <https://github.com/omribenami/Omarchy-AI>

<div align="center">

https://github.com/user-attachments/assets/ea736181-9cf3-423a-b7d5-91a895fe6589

</div>

This page is that product's marketplace front door. The marketplace still
lists one Quattro plugin, the settings panel (`omarchy-ai.settings`).
`omarchy plugin add` does not install the daemon, wake models, or the rest
of the desktop plugins. The bar icon still loads. Without the assistant,
the panel explains how to install Omarchy-AI. With the assistant installed,
the same panel is the settings UI.

## Features

- **It operates the whole machine.** Desktop, windows and workspaces, its
  own terminals and yours, a real browser, files, system administration,
  and code through Claude Code or Codex, with about 90 typed tools and all
  of Omarchy's ~230 commands behind one voice.
- **Whole jobs, not single commands.** A background Task Runtime plans the
  job, routes each step to the right worker, and certifies the result from
  evidence, not from its own claims.
- **Wake word and overlays.** Say the wake word ("omachy"), press
  **Super + `**, or type with **Super + Ctrl + `**. Watchdog, task, and
  routine HUDs stay on screen, and a waiting approval floats as an envelope.
- **Asks before anything risky.** Installs, pushes, service restarts,
  deletes, and root need your OK. A waiting approval is announced out loud
  with Approve / Deny; root needs a click, not just a spoken yes.
- **Works alongside you.** Its commands run in its own terminals, so it
  never takes your keyboard. "Tell me when the build finishes" sets up a
  real watch, and the assistant wakes up to do the next step you asked for.
- **Phone and TV.** From a paired phone, talk or type, watch the desktop
  live, or send the picture to the TV. Cast screen and audio to a paired
  Android TV or projector. While casting, the TV's microphone can carry the
  conversation.

**Phone session**: mirror the screen to your phone and operate the PC by talking to Omarchy.

<div align="center">

https://github.com/user-attachments/assets/7abed3fa-ed55-4835-b77a-4d0a1ab85f1f

</div>

**Phone bridge**: talk from a paired phone to Omarchy while mirroring the PC to Android TVs in your network.

<div align="center">

https://github.com/user-attachments/assets/6d20a7b9-3806-4248-be12-83bdddf63f66

</div>

## Install the full assistant

Download a GitHub Release, or install from source with `install.sh`:

- [Omarchy-AI — Installation](https://github.com/omribenami/Omarchy-AI#installation)
- Project home: <https://github.com/omribenami/Omarchy-AI>

`install.sh` installs the Python daemon, wake models, desktop plugins, and
this settings panel. That is the install that runs Omarchy-AI. After the
daemon is running, open **Omarchy-AI** on the bar, choose a provider, save
a key, and apply the change so the service restarts with it.

`omarchy plugin add` is not that install. It does not run the daemon.

## Settings panel only

`omarchy plugin add` installs this bar widget and nothing else:

```bash
omarchy plugin add https://github.com/omribenami/omarchy-ai-plugin.git --enable
```

Omarchy clones this repository into
`~/.config/omarchy/plugins/omarchy-ai.settings`, validates `manifest.json`,
and can enable the widget in the same step. Plugins run as unsandboxed code
inside the shell; read the files before you confirm. This command does not
start the daemon and does not install Omarchy-AI.

Open **Omarchy-AI** on the bar. The panel looks up `omarchy-ai-settings`
when it opens. No path in `Panel.qml` has to be edited first. If the
assistant is installed, the panel loads settings. If it is not, the panel
stays open and shows how to install the full assistant from GitHub
Releases or `install.sh`.

The widget has no default bar section. If the icon does not show up where
you want it, place it on the right:

```bash
omarchy bar move omarchy-ai.settings --section right
```

If `bash install.sh` from Omarchy-AI has already installed
`omarchy-ai.settings`, keep that copy. It is the same plugin id, and
Omarchy will refuse a second one. `install.sh` still installs the daemon
and the rest of the desktop plugins. This marketplace command does not
replace that.

## Remove

```bash
omarchy plugin remove omarchy-ai.settings
```

Removal disables the widget and deletes this git checkout. It does not
uninstall the Omarchy-AI daemon, your API keys, or
`~/.config/omarchy-ai/`.

## How the panel finds the assistant

The widget does not bake an install path, and enabling it does not require
a path edit. `resolve-settings.sh` looks up `omarchy-ai-settings` when the
panel opens:

1. `OMARCHY_AI_SETTINGS`, when that variable is an executable file.
2. The user service `omarchy-ai.service` written by `install.sh`
   (`WorkingDirectory/.venv/bin/omarchy-ai-settings`, or the venv named
   on `ExecStart`).
3. `omarchy-ai-settings` on `PATH`.
4. The newest fast-install tree under
   `~/.local/share/omachy-ai-releases/omarchy-ai-<version>-linux-x86_64/`.
5. The newest self-update tree under
   `~/.local/share/omarchy-ai/releases/`.

`XDG_CONFIG_HOME` and `XDG_DATA_HOME` are honored. Nothing in this plugin
downloads or installs the assistant. When none of those locations has the
command, the panel explains the Releases / `install.sh` install and keeps
working as a bar widget.

`omarchy plugin update` checks this repository out again. The lookup ships
in the plugin, so an update does not put a path placeholder back.

## License

MIT. Copyright (c) 2026 Omri Ben-Ami. See [LICENSE](LICENSE).
