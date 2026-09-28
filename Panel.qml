import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy-ai.settings"
  ipcTarget: "omarchy-ai.settings"
  manageIpc: false // This panel supplies its own handler including setLive.

  readonly property string py: "@OMARCHY_AI_SETTINGS@"

  property var snapshot: ({})
  property bool loaded: false
  property bool dirty: false
  property bool restarting: false
  property bool apiKeyEditing: false
  property bool gatewayKeyEditing: false
  property var pasteTarget: null
  readonly property string selectedProvider: fields.provider || "openai"
  readonly property bool geminiSelected: fields.provider === "gemini"
  readonly property bool omarchySelected: fields.provider === "omarchy"
  readonly property var selectedKey: omarchySelected ? (snapshot.vercel_gateway_api_key || ({})) : geminiSelected ? (snapshot.gemini_api_key || ({})) : (snapshot.api_key || ({}))
  readonly property var gatewayKey: snapshot.vercel_gateway_api_key || ({})
  onSelectedProviderChanged: { apiKeyEditing = false; apiKeyFieldTop.text = "" }
  property string statusMessage: ""
  property string statusTone: "info" // "info" | "ok" | "error"

  readonly property var fields: snapshot.fields || ({})
  readonly property var wakeModels: snapshot.wake_models || []
  readonly property var displayModes: snapshot.watchdog_display_modes || ["feed", "visualizer", "both"]
  readonly property var voiceOptions: snapshot.voice_options || ["marin"]

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color statusColor: statusTone === "error" ? Color.urgent : (statusTone === "ok" ? Color.accent : Color.muted)

  property bool live: false
  readonly property color liveColor: live ? "#39ff88" : "#ff5f5f"

  property var _queue: []

  function _enqueue(argv, cb, stdinText) {
    root._queue.push({ argv: argv, cb: cb, stdinText: stdinText })
    root._processQueue()
  }

  function _processQueue() {
    if (settingsProc.running || settingsProc._cb !== null) return
    if (root._queue.length === 0) return
    var next = root._queue.shift()
    settingsProc._cb = next.cb
    settingsProc._stdinText = next.stdinText
    settingsProc.command = next.argv
    settingsProc.running = true
    settingsTimeout.restart()
  }

  function _finishProcess(result) {
    settingsTimeout.stop()
    var cb = settingsProc._cb
    settingsProc._cb = null
    if (cb) cb(result)
    Qt.callLater(root._processQueue)
  }

  Process {
    id: settingsProc
    stdinEnabled: true
    onStarted: {
      if (_stdinText !== undefined && _stdinText !== null) write(_stdinText + "\n")
      // Do not retain a second copy of a secret for the lifetime of the helper.
      _stdinText = null
    }
    onRunningChanged: if (!running) settingsExitTimer.restart()
    property var _cb: null
    property var _stdinText: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = null
        try {
          result = text.trim() ? JSON.parse(text) : { error: "Settings helper returned no response" }
        } catch (e) {
          result = { error: "settings helper returned invalid output" }
        }
        if (settingsProc._cb !== null) root._finishProcess(result)
      }
    }
  }

  Timer {
    id: settingsExitTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (settingsProc._cb !== null)
        root._finishProcess({ error: "Settings helper exited without a response" })
      else root._processQueue()
    }
  }

  Timer {
    id: settingsTimeout
    interval: 30000
    repeat: false
    onTriggered: {
      if (settingsProc._cb !== null)
        root._finishProcess({ error: "Settings helper timed out" })
      if (settingsProc.running) settingsProc.running = false
    }
  }

  function fetchSnapshot() {
    root._enqueue([root.py, "get"], function(result) {
      if (result && !result.error) {
        root.snapshot = result
        root.loaded = true
      } else if (result) {
        root.statusTone = "error"
        root.statusMessage = result.error
      }
    })
  }

  function setField(key, jsonValue, successMessage) {
    root._enqueue([root.py, "set", key, jsonValue], function(result) {
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else if (result) {
        root.snapshot = result
        root.dirty = true
        root.statusTone = "ok"
        root.statusMessage = successMessage || "Saved — restart to apply"
      } else {
        root.statusTone = "error"
        root.statusMessage = "No response from settings helper"
      }
    })
  }

  function saveApiKey(key) {
    var trimmed = (key || "").trim()
    if (trimmed.length === 0) {
      root.statusTone = "error"
      root.statusMessage = "Paste a key first"
      return
    }
    root.statusTone = "info"
    root.statusMessage = "Saving conversation key…"
    var command = root.omarchySelected ? "set-vercel-gateway-api-key" : root.geminiSelected ? "set-gemini-api-key" : "set-api-key"
    root._enqueue([root.py, command], function(result) {
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else if (result) {
        root.snapshot = result
        root.dirty = true
        root.statusTone = "ok"
        root.statusMessage = "API key saved — restart to apply"
        apiKeyFieldTop.text = ""
        root.apiKeyEditing = false
      } else {
        root.statusTone = "error"
        root.statusMessage = "No response from settings helper"
      }
    }, trimmed)
  }

  function saveGatewayKey(key) {
    var trimmed = (key || "").trim()
    if (trimmed.length === 0) {
      root.statusTone = "error"
      root.statusMessage = "Paste a Gateway key first"
      return
    }
    root.statusTone = "info"
    root.statusMessage = "Saving Jev Gateway key…"
    root._enqueue([root.py, "set-vercel-gateway-api-key"], function(result) {
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else if (result) {
        root.snapshot = result
        root.dirty = true
        root.statusTone = "ok"
        root.statusMessage = "Jev Gateway key saved — restart to apply"
        gatewayKeyField.text = ""
        root.gatewayKeyEditing = false
      } else {
        root.statusTone = "error"
        root.statusMessage = "No response from settings helper"
      }
    }, trimmed)
  }

  // Quickshell's panel-level keyboard surface can prevent a compositor from
  // delivering Ctrl+V to an otherwise focused password field. Keep a direct
  // Wayland clipboard path here as a reliable fallback; the value remains
  // only in this masked field and is never printed or logged.
  function pasteApiKey(target) {
    root.pasteTarget = target
    if (!pasteKeyProc.running) pasteKeyProc.running = true
  }

  Process {
    id: pasteKeyProc
    command: ["wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.length > 0) {
          if (root.pasteTarget) {
            root.pasteTarget.text = text
            root.pasteTarget.forceActiveFocus()
          }
        } else {
          root.statusTone = "error"
          root.statusMessage = "Clipboard has no text to paste"
        }
        root.pasteTarget = null
      }
    }
  }

  function configureSudo(password) {
    if (!password || password.length === 0) {
      root.statusTone = "error"
      root.statusMessage = "Enter your password first"
      return
    }
    root._enqueue([root.py, "configure-sudo"], function(result) {
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else if (result) {
        root.snapshot = result
        root.setField("sudo_access_enabled", "true", "Sudo Access enabled — Omachy can now complete sudo prompts")
        root.statusTone = "ok"
        root.statusMessage = "Sudo Access saved in GNOME Keyring"
      } else {
        root.statusTone = "error"
        root.statusMessage = "Could not approve sudo"
      }
    }, password)
  }

  function forgetSudo() {
    root._enqueue([root.py, "forget-sudo"], function(result) {
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else {
        root.snapshot = result || ({})
        root.setField("sudo_access_enabled", "false", "Sudo Access disabled and password removed")
      }
    })
  }

  function setApprovalPin(pin) {
    if (!pin || pin.length < 4) {
      root.statusTone = "error"
      root.statusMessage = "The approval PIN needs at least 4 characters"
      return
    }
    root._enqueue([root.py, "set-approval-pin"], function(result) {
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else if (result) {
        root.snapshot = result
        root.statusTone = "ok"
        root.statusMessage = "Approval PIN saved — paired phones can now approve tasks"
      } else {
        root.statusTone = "error"
        root.statusMessage = "Could not save the approval PIN"
      }
    }, pin)
  }

  function forgetApprovalPin() {
    root._enqueue([root.py, "forget-approval-pin"], function(result) {
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else {
        root.snapshot = result || ({})
        root.statusTone = "ok"
        root.statusMessage = "Approval PIN removed — phones can no longer approve tasks"
      }
    })
  }

  property bool pairing: false
  property string qrImageBase64: ""
  property string qrUrl: ""
  property real qrExpiresAt: 0
  readonly property int pairedCount: snapshot.phone_bridge_paired_count || 0

  function pairPhone() {
    root.pairing = true
    root.qrImageBase64 = ""
    root._enqueue([root.py, "pair-phone"], function(result) {
      root.pairing = false
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else if (result) {
        root.qrImageBase64 = result.qr_png_base64
        root.qrUrl = result.url
        root.qrExpiresAt = result.expires_at
        root.statusTone = "info"
        root.statusMessage = "Scan within 5 minutes"
      }
    })
  }

  function revokePhones() {
    root._enqueue([root.py, "revoke-phones"], function(result) {
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else if (result) {
        root.snapshot = result
        root.statusTone = "ok"
        root.statusMessage = "All paired phones revoked"
      }
    })
  }

  function setWakeModels(vals) {
    root._enqueue([root.py, "set", "custom_wake_model_paths", JSON.stringify(vals)], function(result) {
      if (result && result.error) {
        root.statusTone = "error"
        root.statusMessage = result.error
      } else if (result) {
        root.snapshot = result
        root.dirty = true
        root.statusTone = "ok"
        root.statusMessage = "Wake models updated — restart to apply"
      }
      wakeModelsSelect.values = (root.snapshot.fields && root.snapshot.fields.custom_wake_model_paths) || []
    })
  }

  function doRestart() {
    root.restarting = true
    root.statusTone = "info"
    root.statusMessage = "Restarting…"
    root._enqueue([root.py, "restart"], function(result) {
      root.restarting = false
      if (result && result.restarted) {
        root.dirty = false
        root.statusTone = "ok"
        root.statusMessage = "Daemon restarted"
      } else {
        root.statusTone = "error"
        root.statusMessage = (result && result.reason) || "Restart failed"
      }
    })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function setLive(payloadJson: string): string {
      try {
        var p = JSON.parse(payloadJson || "{}")
        root.live = !!p.live
      } catch (e) {
        console.warn("omarchy-ai.settings: could not parse setLive payload:", e)
      }
      return "ok"
    }
  }

  onOpenedChanged: if (opened) { root.statusMessage = ""; root.statusTone = "info"; fetchSnapshot() }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: Component {
      Item {
        anchors.fill: parent

        Image {
          anchors.fill: parent
          source: "file:///usr/share/pixmaps/omarchy.png"
          sourceSize.width: Style.bar.iconCanvas * 2
          sourceSize.height: Style.bar.iconCanvas * 2
          fillMode: Image.PreserveAspectFit
        }

        Rectangle {
          width: Math.max(5, Math.round(parent.width * 0.32))
          height: width
          radius: width / 2
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          color: root.liveColor
          border.color: Qt.darker(Color.background, 1.6)
          border.width: 1

          Behavior on color { ColorAnimation { duration: 200 } }
        }
      }
    }
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Omarchy AI Settings"
    onPressed: root.toggle()
  }


  property string section: "voice"
  property bool activating: false
  property int glitchFrame: 0
  readonly property string assistantState: live ? "active" : ((snapshot.assistant || {}).state || "offline")
  Timer { interval: 160; running: root.opened; repeat: true; onTriggered: root.glitchFrame = (root.glitchFrame + 1) % 35 }
  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: if (!settingsProc.running && root._queue.length === 0) root.fetchSnapshot() }
  function activateAssistant() {
    root.activating = true
    root._enqueue([root.py, "activate"], function(result) {
      root.activating = false
      root.statusTone = result.error ? "error" : "ok"
      root.statusMessage = result.error || "Starting Omachy — speak into your computer microphone"
      root.fetchSnapshot()
    })
  }
  KeyboardPanel {
    id: panel
    anchorItem: button; owner: root; bar: root.bar; open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // PanelKeyCatcher handles keys before its children. Password fields
      // must own Ctrl+V (and all regular editing keys) once focused.
      blocked: apiKeyFieldTop.activeFocus || gatewayKeyField.activeFocus || sudoPasswordField.activeFocus || approvalPinField.activeFocus
      onCloseRequested: root.close()
      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)
        Row {
          width: parent.width; spacing: Style.space(14)
          Text {
            text: root.glitchFrame < 2 ? "[ /#_#\\ ]\n <|:::|>" : "[ o_o ]\n <|:::|>"
            textFormat: Text.PlainText
            color: Color.accent; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body
            opacity: root.glitchFrame === 1 ? 0.65 : 1
          }
          Column {
            spacing: Style.space(4)
            Text { text: "Omachy"; color: root.fg; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Text {
              text: root.assistantState === "active" ? "Conversation active" : root.assistantState === "starting" ? "Connecting…" : root.assistantState === "listening" ? "Ready · listening for your wake word" : "Assistant offline"
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.72); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption
            }
          }
        }
        Button {
          width: parent.width
          text: root.activating || root.assistantState === "starting" ? "Starting…" : root.assistantState === "active" ? "Omachy is active" : "Activate Omachy"
          iconText: "󰍬"; bordered: true; selected: true; focusable: true
          foreground: root.fg; accent: Color.accent; fontFamily: root.bar.fontFamily
          enabled: !root.activating && root.assistantState === "listening"
          opacity: enabled ? 1 : 0.55
          onClicked: root.activateAssistant()
        }
        Text {
          width: parent.width; wrapMode: Text.WordWrap
          text: (root.snapshot.assistant && root.snapshot.assistant.error_detail) || (root.dirty ? "Changes saved · apply below to use them" : "Running provider: " + ((root.snapshot.assistant && root.snapshot.assistant.provider) || "offline"))
          color: root.snapshot.assistant && root.snapshot.assistant.error_detail ? Color.urgent : Color.muted
          font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption
        }
        Column {
          width: parent.width; spacing: Style.space(6)
          PanelSectionHeader { text: "AI PROVIDER & ACCESS"; foreground: root.fg; fontFamily: root.bar.fontFamily }
          Dropdown { width: parent.width; showLabel: true; label: "Conversation model"; foreground: root.fg; background: Color.popups.background; fontFamily: root.bar.fontFamily; value: root.selectedProvider; options: [{value: "openai", label: "OpenAI Live"}, {value: "gemini", label: "Gemini Live"}, {value: "omarchy", label: "Gateway voice"}]; onChanged: function(v) { root.setField("provider", JSON.stringify(v), "Conversation model updated — restart to apply") } }
          Dropdown { visible: root.omarchySelected; width: parent.width; showLabel: true; label: "Gateway reply model"; foreground: root.fg; background: Color.popups.background; fontFamily: root.bar.fontFamily; value: root.fields.omarchy_model_choice || "gemini"; options: [{value: "gemini", label: "Gemini (Gateway)"}, {value: "openai", label: "OpenAI (Gateway)"}, {value: "jev", label: "Jev policy + Gateway text"}]; onChanged: function(v) { root.setField("omarchy_model_choice", JSON.stringify(v), "Model updated — restart to apply") } }
          Text { width: parent.width; wrapMode: Text.WordWrap; text: root.selectedKey.set ? "Conversation key saved" : root.omarchySelected ? "Enter your Vercel AI Gateway key for Gateway voice." : root.geminiSelected ? "Enter your Google AI Studio key for Gemini Live." : "Enter your OpenAI key for OpenAI Live."; color: root.selectedKey.set ? Color.muted : Color.urgent; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
          Row {
            width: parent.width; spacing: Style.space(8)
            TextField { id: apiKeyFieldTop; visible: !root.selectedKey.set || root.apiKeyEditing; width: parent.width - saveKeyButtonTop.width - pasteKeyButtonTop.width - Style.space(16); password: true; placeholderText: root.omarchySelected ? "Vercel AI Gateway key" : root.geminiSelected ? "Google AI Studio key" : "OpenAI key"; foreground: root.fg; font.family: root.bar.fontFamily; onAccepted: root.saveApiKey(text) }
            Button { id: pasteKeyButtonTop; text: "Paste"; bordered: true; foreground: root.fg; fontFamily: root.bar.fontFamily; onClicked: root.pasteApiKey(apiKeyFieldTop) }
            Button { id: saveKeyButtonTop; text: root.selectedKey.set && !root.apiKeyEditing ? "Edit key" : "Save key"; bordered: true; foreground: root.fg; fontFamily: root.bar.fontFamily; onClicked: { if (root.selectedKey.set && !root.apiKeyEditing) root.apiKeyEditing = true; else root.saveApiKey(apiKeyFieldTop.text) } }
          }
          Text { visible: !root.omarchySelected; width: parent.width; wrapMode: Text.WordWrap; text: root.gatewayKey.set ? "Jev access key saved. Jev uses Vercel AI Gateway for desktop and browser decisions." : "Jev desktop and browser actions need a Vercel AI Gateway key. A separate TypeSafe token is not used by this integration."; color: root.gatewayKey.set ? Color.muted : Color.urgent; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
          Row {
            visible: !root.omarchySelected
            width: parent.width; spacing: Style.space(8)
            TextField { id: gatewayKeyField; visible: !root.gatewayKey.set || root.gatewayKeyEditing; width: parent.width - saveGatewayButton.width - pasteGatewayButton.width - Style.space(16); password: true; placeholderText: "Jev / Vercel AI Gateway key"; foreground: root.fg; font.family: root.bar.fontFamily; onAccepted: root.saveGatewayKey(text) }
            Button { id: pasteGatewayButton; text: "Paste"; bordered: true; foreground: root.fg; fontFamily: root.bar.fontFamily; onClicked: root.pasteApiKey(gatewayKeyField) }
            Button { id: saveGatewayButton; text: root.gatewayKey.set && !root.gatewayKeyEditing ? "Edit key" : "Save key"; bordered: true; foreground: root.fg; fontFamily: root.bar.fontFamily; onClicked: { if (root.gatewayKey.set && !root.gatewayKeyEditing) root.gatewayKeyEditing = true; else root.saveGatewayKey(gatewayKeyField.text) } }
          }
          Text {
            visible: root.statusMessage.length > 0
            width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
            text: root.statusMessage; color: root.statusColor
            font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption
          }
        }
        ButtonGroup {
          width: parent.width; foreground: root.fg; fontFamily: root.bar.fontFamily
          fontSize: Style.font.bodySmall; value: root.section
          options: [{value: "voice", label: "Voice"}, {value: "connections", label: "Connections"}, {value: "appearance", label: "Appearance"}]
          onChanged: function(v) { root.section = v; scrollArea.contentY = 0 }
        }
        PanelSeparator { foreground: root.fg }
        Flickable {
          id: scrollArea
          width: parent.width
          height: Math.min(scrollColumn.implicitHeight, Math.max(Style.space(100), panel.availableCardHeight - Style.space(480)))
          contentWidth: width; contentHeight: scrollColumn.implicitHeight
          clip: true; boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          Column {
            id: scrollColumn
            width: parent.width - Style.space(10); spacing: Style.space(12)
        Column {
          visible: root.section === "voice"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "WAKE WORD"; foreground: root.fg; fontFamily: root.bar.fontFamily }

          MultiSelect {
            id: wakeModelsSelect
            width: parent.width
            label: "Active models"
            placeholderText: "Search models..."
            noSelectionText: "None active"
            foreground: root.fg
            background: Color.popups.background
            fontFamily: root.bar.fontFamily
            values: root.fields.custom_wake_model_paths || []
            options: {
              var opts = []
              for (var i = 0; i < root.wakeModels.length; i++)
                opts.push({ value: root.wakeModels[i].path, label: root.wakeModels[i].name })
              return opts
            }
            onChanged: function(vals) { root.setWakeModels(vals) }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.wakeModels.length === 0
            text: "No trained *.onnx models found under ~/.config/omarchy-ai/wake_models/"
            color: Qt.darker(root.fg, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Wake sensitivity  " + Number(root.fields.wake_threshold !== undefined ? root.fields.wake_threshold : 0.5).toFixed(2)
            color: root.fg
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSlider {
            id: thresholdSlider
            width: parent.width
            bar: root.bar
            minimum: 0.1
            maximum: 0.9
            step: 0.05
            value: root.fields.wake_threshold !== undefined ? root.fields.wake_threshold : 0.5
            onReleased: function(v) { root.setField("wake_threshold", String(Math.round(v * 100) / 100)) }
          }
        }

        PanelSeparator { foreground: root.fg; visible: root.section === "voice" }


        Column {
          visible: root.section === "voice"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "VOICE"; foreground: root.fg; fontFamily: root.bar.fontFamily }

          Dropdown {
            id: voiceDropdown
            width: parent.width
            showLabel: false
            foreground: root.fg
            background: Color.popups.background
            fontFamily: root.bar.fontFamily
            value: root.fields.voice || "marin"
            options: root.voiceOptions
            onChanged: function(v) { root.setField("voice", JSON.stringify(v), "Voice updated — restart to apply") }
          }
        }

        PanelSeparator { foreground: root.fg; visible: root.section === "voice" }

                Column {
          visible: root.section === "connections"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "MYAPI"; foreground: root.fg; fontFamily: root.bar.fontFamily }

          Toggle {
            id: myapiToggle
            width: parent.width
            label: "Enable MyApi"
            description: "Show the MyApi dashboard in the bar and allow connected services."
            foreground: root.fg
            checked: root.fields.myapi_enabled !== undefined ? !!root.fields.myapi_enabled : false
            onClicked: root.setField("myapi_enabled", myapiToggle.checked ? "false" : "true", "MyApi " + (myapiToggle.checked ? "disabled" : "enabled — look for its icon in the bar"))
          }
        }
        PanelSeparator { foreground: root.fg; visible: root.section === "connections" }

        Column {
          visible: root.section === "connections"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "SUDO ACCESS"; foreground: "#ffd24d"; fontFamily: root.bar.fontFamily }

          Rectangle {
            width: parent.width
            height: sudoWarning.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: "#5a4500"
            border.color: "#ffd24d"
            border.width: 1
            Text {
              id: sudoWarning
              anchors.fill: parent
              anchors.margins: Style.space(9)
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "DANGER: When enabled, Omachy can use sudo for commands you ask it to run. Turn this off when you do not want autonomous administrator access."
              color: "#ffe7a0"
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: (root.fields.sudo_access_enabled && root.snapshot.sudo_approval && root.snapshot.sudo_approval.stored)
              ? "Sudo Access is enabled. Your password is stored in GNOME Keyring, never shown to Omachy."
              : "Save your system password once to GNOME Keyring, then enable or disable Omachy's sudo access whenever you choose."
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: Qt.darker(root.fg, 1.4)
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: sudoPasswordField
              width: parent.width - saveSudoButton.width - Style.space(8)
              password: true
              placeholderText: "System password"
              foreground: root.fg
              font.family: root.bar.fontFamily
              onAccepted: { root.configureSudo(text); text = "" }
            }

            Button {
              id: saveSudoButton
              text: "Save & enable"
              bordered: true
              foreground: root.fg
              fontFamily: root.bar.fontFamily
              onClicked: { root.configureSudo(sudoPasswordField.text); sudoPasswordField.text = "" }
            }
          }

          Toggle {
            id: sudoAccessToggle
            width: parent.width
            label: "Enable Sudo Access"
            description: "Allows Omachy to enter the saved password at sudo prompts."
            foreground: "#ffd24d"
            checked: root.fields.sudo_access_enabled !== undefined ? !!root.fields.sudo_access_enabled : false
            onClicked: {
              if (!sudoAccessToggle.checked && !(root.snapshot.sudo_approval && root.snapshot.sudo_approval.stored)) {
                root.statusTone = "error"
                root.statusMessage = "Save a password first"
                root.fetchSnapshot()
              } else {
                root.setField("sudo_access_enabled", sudoAccessToggle.checked ? "false" : "true", sudoAccessToggle.checked ? "Sudo Access disabled" : "Sudo Access enabled")
              }
            }
          }

          Button {
            width: parent.width
            text: "Forget saved password and disable"
            bordered: true
            foreground: "#ffd24d"
            fontFamily: root.bar.fontFamily
            onClicked: root.forgetSudo()
          }
        }

        PanelSeparator { foreground: root.fg; visible: root.section === "connections" }

                Column {
          visible: root.section === "connections"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "PHONE BRIDGE"; foreground: root.fg; fontFamily: root.bar.fontFamily }

          Toggle {
            id: phoneBridgeToggle
            width: parent.width
            label: "Enable phone access"
            description: "A local page a phone on this network can open to talk to Omarchy. Pairing is required — an unpaired phone can't use it."
            foreground: root.fg
            checked: root.fields.phone_bridge_enabled !== undefined ? !!root.fields.phone_bridge_enabled : false
            onClicked: root.setField("phone_bridge_enabled", phoneBridgeToggle.checked ? "false" : "true", "Phone bridge updated — restart to apply")
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.pairedCount > 0
            text: root.pairedCount + (root.pairedCount === 1 ? " phone paired" : " phones paired")
            color: Qt.darker(root.fg, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              id: qrButton
              text: root.pairing ? "Generating…" : "Pair a phone"
              bordered: true
              foreground: root.fg
              fontFamily: root.bar.fontFamily
              enabled: !root.pairing && !!root.fields.phone_bridge_enabled
              onClicked: root.pairPhone()
            }

            Button {
              text: "Revoke All"
              bordered: true
              foreground: "#ff6b6b"
              fontFamily: root.bar.fontFamily
              enabled: root.pairedCount > 0
              onClicked: root.revokePhones()
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.qrImageBase64.length > 0

            Image {
              width: 180
              height: 180
              anchors.horizontalCenter: parent.horizontalCenter
              source: root.qrImageBase64.length > 0 ? ("data:image/png;base64," + root.qrImageBase64) : ""
              fillMode: Image.PreserveAspectFit
              smooth: false
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: "Scan with the phone's camera — expires in 5 minutes"
              color: Qt.darker(root.fg, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Button {
              text: "Hide"
              bordered: true
              foreground: root.fg
              fontFamily: root.bar.fontFamily
              anchors.horizontalCenter: parent.horizontalCenter
              onClicked: root.qrImageBase64 = ""
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: (root.snapshot.approval_pin && root.snapshot.approval_pin.set)
              ? "Approval PIN is set. A paired phone can approve waiting tasks by entering it (5 wrong tries lock it for 15 min)."
              : "Set an approval PIN to approve waiting tasks from a paired phone. Not your login password; stored only as a hash."
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: Qt.darker(root.fg, 1.4)
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: approvalPinField
              width: parent.width - saveApprovalPinButton.width - Style.space(8)
              password: true
              placeholderText: (root.snapshot.approval_pin && root.snapshot.approval_pin.set) ? "New approval PIN" : "Approval PIN"
              foreground: root.fg
              font.family: root.bar.fontFamily
              onAccepted: { root.setApprovalPin(text); text = "" }
            }

            Button {
              id: saveApprovalPinButton
              text: "Save PIN"
              bordered: true
              foreground: root.fg
              fontFamily: root.bar.fontFamily
              onClicked: { root.setApprovalPin(approvalPinField.text); approvalPinField.text = "" }
            }
          }

          Button {
            width: parent.width
            visible: !!(root.snapshot.approval_pin && root.snapshot.approval_pin.set)
            text: "Remove approval PIN"
            bordered: true
            foreground: "#ff6b6b"
            fontFamily: root.bar.fontFamily
            onClicked: root.forgetApprovalPin()
          }
        }
        PanelSeparator { foreground: root.fg; visible: root.section === "connections" }

                Column {
          visible: root.section === "connections"
          width: parent.width
          spacing: Style.space(10)

          // API key editor is shown at the top of the panel.
        }

        PanelSeparator { foreground: root.fg; visible: root.section === "connections" }

                Column {
          visible: root.section === "appearance"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "CONVERSATION OVERLAY"; foreground: root.fg; fontFamily: root.bar.fontFamily }

          Toggle {
            id: watchdogToggle
            width: parent.width
            label: "Show overlay"
            description: "Show conversation activity while Omachy is talking."
            foreground: root.fg
            checked: root.fields.watchdog_enabled !== undefined ? !!root.fields.watchdog_enabled : true
            onClicked: root.setField("watchdog_enabled", watchdogToggle.checked ? "false" : "true")
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Display mode"
            color: Qt.darker(root.fg, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          ButtonGroup {
            width: parent.width
            foreground: root.fg
            background: Color.background
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            value: root.fields.watchdog_display_mode || "visualizer"
            options: [
              { value: "feed", label: "Text feed" },
              { value: "visualizer", label: "ASCII visualizer" },
              { value: "both", label: "Both" }
            ]
            onChanged: function(v) { root.setField("watchdog_display_mode", JSON.stringify(v), "Display mode updated — restart to apply") }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "ASCII reacts to the assistant’s voice. Choose the activity feed, visualizer, or both."
            color: Qt.darker(root.fg, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Toggle {
            id: tasksHudToggle
            width: parent.width
            label: "Open task HUD on call"
            description: "Show every task the assistant currently has when you call her."
            foreground: root.fg
            checked: root.fields.tasks_hud_on_call !== undefined ? !!root.fields.tasks_hud_on_call : false
            onClicked: root.setField("tasks_hud_on_call", tasksHudToggle.checked ? "false" : "true")
          }

          Toggle {
            id: routinesHudToggle
            width: parent.width
            label: "Open routines HUD on call"
            description: "Show active scheduled and cron routines when you call her."
            foreground: root.fg
            checked: root.fields.routines_hud_on_call !== undefined ? !!root.fields.routines_hud_on_call : false
            onClicked: root.setField("routines_hud_on_call", routinesHudToggle.checked ? "false" : "true")
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Text chat"
            color: Qt.darker(root.fg, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          ButtonGroup {
            width: parent.width
            foreground: root.fg
            background: Color.background
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            value: root.fields.text_chat_mode || "keybinding"
            options: [
              { value: "keybinding", label: "On key" },
              { value: "always", label: "Always on screen" }
            ]
            onChanged: function(v) { root.setField("text_chat_mode", JSON.stringify(v), "Text chat updated") }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Type to the assistant instead of talking. " + (root.snapshot.text_chat_key || "SUPER + CTRL + `")
                  + " opens it (the voice key plus Ctrl); Esc closes it. Always on screen keeps it in the corner."
            color: Qt.darker(root.fg, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator { foreground: root.fg; visible: root.section === "appearance" }


            Text {
              visible: root.section === "appearance"
              width: parent.width; wrapMode: Text.WordWrap
              text: "The header’s ASCII glitches animate only while this panel is open."
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.72); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption
            }
          }
        }
        Button {
          visible: root.dirty || root.assistantState === "offline"
          width: parent.width; text: root.restarting ? "Restarting…" : root.dirty ? "Apply saved changes" : "Start assistant"
          bordered: true; focusable: true; foreground: root.fg; fontFamily: root.bar.fontFamily
          // Applying a saved preference must remain clickable while the
          // daemon is running.  The restart helper still reports a busy
          // conversation rather than silently doing nothing, and the panel
          // keeps the dirty state until a restart actually succeeds.
          enabled: !root.restarting
          onClicked: root.doRestart()
        }
      }
    }
  }
}
