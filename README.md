# Omarchy AI Settings

Bar widget for the [Omarchy](https://omarchy.org) shell. It opens wake-word
models, the conversation overlay, voice, and the other assistant settings
from an icon on the bar.

Plugin id: `omarchy-ai.settings`.

This repository is the marketplace listing for that one widget. Installing
it from here adds the settings bar widget and its discovery entry in the
shell. The voice assistant itself — the Python daemon, `install.sh`, wake
models, and the rest of the desktop plugins — is the
[Omarchy AI](https://github.com/omribenami/Omarchy-AI) project. Install that
from a GitHub Release or from source with `install.sh`. The steps are in the
[Omarchy AI installation guide](https://github.com/omribenami/Omarchy-AI#installation).

## Install

```bash
omarchy plugin add https://github.com/omribenami/omarchy-ai-settings.git --enable
```

Omarchy clones this repository into
`~/.config/omarchy/plugins/omarchy-ai.settings`, validates `manifest.json`,
and can enable the widget in the same step. Plugins run as unsandboxed code
inside the shell; read the files before you confirm.

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

## Full Omarchy AI install

The panel configures a daemon that this repository does not ship. Install
the assistant from Omarchy AI, then come back to the bar icon:

- Release install and source install:
  [Omarchy AI — Installation](https://github.com/omribenami/Omarchy-AI#installation)
- Project home: <https://github.com/omribenami/Omarchy-AI>

After the daemon is running, open **Omarchy AI Settings** on the bar, choose
a provider, save a key, and apply the change so the service restarts with it.

## External dependency

The widget shells out to the `omarchy-ai-settings` command from the Omarchy
AI install. Without that daemon and CLI, the icon can sit on the bar and
every load, save, and restart from the panel fails.

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
