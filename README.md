# Omarchy AI

**Omarchy AI** is a self-hosted, voice-driven **agentic assistant** for
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
of the desktop plugins. A settings icon by itself does nothing useful.
Install the full assistant first.

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

- [Omarchy AI — Installation](https://github.com/omribenami/Omarchy-AI#installation)
- Project home: <https://github.com/omribenami/Omarchy-AI>

`install.sh` installs the Python daemon, wake models, desktop plugins, and
this settings panel, and points the panel at the settings command. That is
the install that runs Omarchy AI. After the daemon is running, open
**Omarchy AI** on the bar, choose a provider, save a key, and apply the
change so the service restarts with it.

`omarchy plugin add` is not that install. It does not run the daemon.

## Settings panel only

Use this only after the assistant is already installed, and only if you want
this marketplace copy of the bar widget:

```bash
omarchy plugin add https://github.com/omribenami/omarchy-ai-settings.git --enable
```

Omarchy clones this repository into
`~/.config/omarchy/plugins/omarchy-ai.settings`, validates `manifest.json`,
and can enable the widget in the same step. Plugins run as unsandboxed code
inside the shell; read the files before you confirm. This command does not
start the daemon.

The widget has no default bar section. If the icon does not show up where
you want it, place it on the right:

```bash
omarchy bar move omarchy-ai.settings --section right
```

If `bash install.sh` from Omarchy AI has already installed
`omarchy-ai.settings`, keep that copy. It is the same plugin id, Omarchy
will refuse a second one, and the installer has already pointed the panel
at the settings CLI (see below).

## Remove

```bash
omarchy plugin remove omarchy-ai.settings
```

Removal disables the widget and deletes this git checkout. It does not
uninstall the Omarchy AI daemon, your API keys, or
`~/.config/omarchy-ai/`.

## Manual setup

The widget shells out to the `omarchy-ai-settings` command from the Omarchy
AI install. Without that daemon and CLI, the icon can sit on the bar and
every load, save, and restart from the panel fails. Marketplace install
does not run the daemon.

`Panel.qml` still calls the CLI through an install-time placeholder:

```qml
readonly property string py: "@OMARCHY_AI_SETTINGS@"
```

`scripts/install-plugins.sh` in Omarchy AI rewrites `@OMARCHY_AI_SETTINGS@`
to the absolute path of `.venv/bin/omarchy-ai-settings` in that install
directory. `omarchy plugin add` does not run that rewrite, so a marketplace
install leaves the placeholder in place. The panel cannot talk to the daemon
until that property is the real executable.

After the assistant is installed, edit the copy Omarchy cloned:

`~/.config/omarchy/plugins/omarchy-ai.settings/Panel.qml`

Replace `@OMARCHY_AI_SETTINGS@` with the absolute path of
`omarchy-ai-settings`:

- Release install: the service keeps running from the extracted directory.
  The CLI is
  `~/.local/share/omachy-ai-releases/omarchy-ai-<version>-linux-x86_64/.venv/bin/omarchy-ai-settings`
  (the fast-install block in the Omarchy AI README unpacks there).
- Source checkout: `<checkout>/.venv/bin/omarchy-ai-settings`.

Confirm the file is executable (`omarchy-ai-settings get` should print JSON),
then reopen the panel. Updating this plugin with `omarchy plugin update`
checks out this repository again and puts the placeholder back, so reapply
the path after an update. Installing the widget through Omarchy AI's
`install.sh` avoids that manual edit.

## License

MIT. Copyright (c) 2026 Omri Ben-Ami. See [LICENSE](LICENSE).
