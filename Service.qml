import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property int refreshIntervalSec: 30
  property int tokenLifetimeDays: 90
  property var vms: []
  property bool refreshing: false
  property bool needsAuth: false
  property bool sshAvailable: false
  property bool httpsAvailable: false
  property bool connectionChecking: true
  property string activeTransport: ""
  property string username: ""
  property string lastError: ""
  property string actionStatus: ""
  property string creationProgress: ""
  property bool shelleyPromptRunning: false
  property string shelleyPromptVmName: ""
  property string shelleyPromptStatus: ""

  property string operation: ""
  property var operationArgs: []
  property bool operationMutation: false
  property string successMessage: ""
  property string targetVmName: ""
  property bool targetPublic: false
  property string outputBuffer: ""
  property string errorBuffer: ""
  property string pendingCreatePrompt: ""
  property string shelleyOutputBuffer: ""
  property string shelleyErrorBuffer: ""

  signal vmCreated(var vm, bool promptPending)
  signal operationFailed(string operation, string message)

  readonly property int remoteStdoutLimitBytes: 262144
  readonly property int remoteStderrLimitBytes: 65536
  readonly property int probeDeadlineSec: 15
  readonly property int operationDeadlineSec: 120
  readonly property int shelleyDeadlineSec: 45

  readonly property string apiScript: "token=$(secret-tool lookup service exe.dev application sco.omexe 2>/dev/null) || exit 77; [ -n \"$token\" ] || exit 77; max_time=$2; case $max_time in ''|*[!0-9]*) exit 64;; esac; printf 'Authorization: Bearer %s\\n' \"$token\" | /usr/bin/curl --fail-with-body --silent --show-error --max-time \"$max_time\" --max-filesize \"$3\" --request POST --header @- --data-binary \"$1\" https://exe.dev/exec"

  function shellCommand(args) {
    return args.map(function(value) { return Util.shellQuote(String(value)) }).join(" ")
  }

  function boundedCommand(command, deadlineSec) {
    var deadline = Math.max(1, Math.min(300, parseInt(String(deadlineSec), 10) || operationDeadlineSec))
    var stdoutBlocks = Math.ceil(remoteStdoutLimitBytes / 4096)
    var stderrBlocks = Math.ceil(remoteStderrLimitBytes / 4096)
    var script = "set +e; umask 077; tmp=$(/usr/bin/mktemp -d) || exit 70; trap '/bin/rm -rf \"$tmp\"' EXIT HUP INT TERM; /usr/bin/mkfifo \"$tmp/out\" \"$tmp/err\" || exit 70; limiter_script='/usr/bin/dd bs=4096 count=\"$1\" iflag=fullblock status=none; extra=$(/usr/bin/dd bs=1 count=1 status=none | /usr/bin/wc -c); [ \"$extra\" -eq 0 ] || exit 98'; /usr/bin/setsid /usr/bin/bash --noprofile --norc -p -c \"$limiter_script\" limiter " + stdoutBlocks + " <\"$tmp/out\" & out_pid=$!; /usr/bin/setsid /usr/bin/bash --noprofile --norc -p -c \"$limiter_script\" limiter " + stderrBlocks + " <\"$tmp/err\" >&2 & err_pid=$!; /usr/bin/setsid \"$@\" >\"$tmp/out\" 2>\"$tmp/err\" & command_pid=$!; watchdog_script='/usr/bin/sleep \"$1\"; : >\"$2\"; kill -TERM -- -\"$3\" 2>/dev/null; /usr/bin/sleep 2; kill -KILL -- -\"$3\" 2>/dev/null'; /usr/bin/setsid /usr/bin/bash --noprofile --norc -p -c \"$watchdog_script\" watchdog " + deadline + " \"$tmp/timed-out\" \"$command_pid\" & timer_pid=$!; wait \"$command_pid\"; command_rc=$?; kill -TERM -- -\"$timer_pid\" 2>/dev/null; /usr/bin/sleep 0.05; kill -KILL -- -\"$timer_pid\" 2>/dev/null; wait \"$timer_pid\" 2>/dev/null; kill -TERM -- -\"$command_pid\" 2>/dev/null; /usr/bin/sleep 0.05; kill -KILL -- -\"$command_pid\" 2>/dev/null; [ -e \"$tmp/timed-out\" ] && command_rc=124; remaining=40; while { kill -0 \"$out_pid\" 2>/dev/null || kill -0 \"$err_pid\" 2>/dev/null; } && [ \"$remaining\" -gt 0 ]; do /usr/bin/sleep 0.05; remaining=$((remaining - 1)); done; out_stuck=0; err_stuck=0; kill -0 \"$out_pid\" 2>/dev/null && { out_stuck=1; kill -TERM -- -\"$out_pid\" 2>/dev/null; }; kill -0 \"$err_pid\" 2>/dev/null && { err_stuck=1; kill -TERM -- -\"$err_pid\" 2>/dev/null; }; /usr/bin/sleep 0.05; [ \"$out_stuck\" -eq 1 ] && kill -KILL -- -\"$out_pid\" 2>/dev/null; [ \"$err_stuck\" -eq 1 ] && kill -KILL -- -\"$err_pid\" 2>/dev/null; wait \"$out_pid\" 2>/dev/null; out_rc=$?; wait \"$err_pid\" 2>/dev/null; err_rc=$?; [ \"$out_stuck\" -eq 1 ] && out_rc=99; [ \"$err_stuck\" -eq 1 ] && err_rc=99; if [ \"$out_rc\" -eq 98 ] || [ \"$err_rc\" -eq 98 ]; then exit 98; fi; if [ \"$out_rc\" -eq 99 ] || [ \"$err_rc\" -eq 99 ]; then exit 99; fi; exit \"$command_rc\""
    return ["/usr/bin/env", "-u", "BASH_ENV", "PATH=/usr/local/bin:/usr/bin:/bin", "/usr/bin/bash", "--noprofile", "--norc", "-p", "-c", script, "omexe-bounded"].concat(command)
  }

  function sshCommand(args, deadlineSec) {
    var command = ["/usr/bin/ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6", "-o", "ConnectionAttempts=1", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2", "exe.dev", shellCommand(args)]
    return boundedCommand(command, deadlineSec)
  }

  function httpsCommand(args, deadlineSec) {
    var deadline = Math.max(1, Math.min(300, parseInt(String(deadlineSec), 10) || operationDeadlineSec))
    var transferDeadline = Math.max(1, deadline - 2)
    var command = ["/usr/bin/env", "-u", "BASH_ENV", "PATH=/usr/local/bin:/usr/bin:/bin", "/usr/bin/bash", "--noprofile", "--norc", "-p", "-c", apiScript, "bash", shellCommand(args), String(transferDeadline), String(remoteStdoutLimitBytes)]
    return boundedCommand(command, deadline)
  }

  function commandFor(transport, args, deadlineSec) {
    return transport === "ssh" ? sshCommand(args, deadlineSec) : httpsCommand(args, deadlineSec)
  }

  function appendCapped(current, value, limit) {
    var combined = String(current || "") + String(value || "")
    return combined.length > limit ? combined.substring(0, limit) : combined
  }

  function compact(value, fallback) {
    var text = String(value || "").replace(/\s+/g, " ").trim() || fallback
    return text.length > 180 ? text.substring(0, 177) + "…" : text
  }

  function errorText(value) {
    if (typeof value === "string") return value
    if (!value || typeof value !== "object") return ""
    if (typeof value.message === "string") return value.message
    if (typeof value.error === "string") return value.error
    if (value.error) return errorText(value.error)
    if (typeof value.detail === "string") return value.detail
    return ""
  }

  function friendlyFailure(currentOperation, raw) {
    var source = String(raw || "").trim()
    var message = ""
    try {
      message = errorText(JSON.parse(source))
    } catch (error) {
      var jsonEnd = source.lastIndexOf("}")
      if (source.charAt(0) === "{" && jsonEnd !== -1) {
        try { message = errorText(JSON.parse(source.substring(0, jsonEnd + 1))) } catch (ignored) {}
      }
    }

    message = compact(message || source.replace(/curl: \(\d+\).*$/i, ""), "")
    var lower = message.toLowerCase()
    if (lower.indexOf("is not available") !== -1) return "That machine name is not available."
    if (lower.indexOf("invalid vm name") !== -1) return "Use 5–52 lowercase letters or digits, separated by single hyphens."
    if (lower.indexOf("command not allowed") !== -1 || lower.indexOf("not allowed by token") !== -1) return "Reconnect exe.dev to update fallback access."
    if (message) return message.charAt(0).toUpperCase() + message.substring(1)
    if (currentOperation === "create") return "Could not create the machine. Try again."
    if (currentOperation === "visibility") return "Could not change web access. Try again."
    if (currentOperation === "list") return "Could not refresh machines."
    return "The exe.dev command failed. Try again."
  }

  function updateConnectionState() {
    needsAuth = !connectionChecking && !sshAvailable && !httpsAvailable
    if (!connectionChecking && sshAvailable && !httpsAvailable && !fallbackProvisionProcess.running)
      fallbackProvisionProcess.running = true
  }

  function recordIdentity(raw) {
    var source = String(raw || "").trim()
    if (!source) return
    try {
      var identity = JSON.parse(source)
      username = String(identity.username || identity.user || identity.name || identity.email || "").split("@")[0]
    } catch (error) {
      username = source.split("@")[0]
    }
  }

  function runArgs(args, nextOperation, pending, success, mutation) {
    if (process.running) return false
    var transport = sshAvailable ? "ssh" : (httpsAvailable ? "https" : "")
    if (!transport) {
      needsAuth = true
      return false
    }
    operation = nextOperation
    operationArgs = args
    operationMutation = Boolean(mutation)
    successMessage = success || ""
    actionStatus = pending || ""
    creationProgress = nextOperation === "create" ? (pending || "Creating machine…") : ""
    lastError = ""
    outputBuffer = ""
    errorBuffer = ""
    activeTransport = transport
    process.command = commandFor(transport, args, operationDeadlineSec)
    process.running = true
    return true
  }

  function retryReadOverHttps() {
    activeTransport = "https"
    outputBuffer = ""
    errorBuffer = ""
    process.command = httpsCommand(operationArgs, operationDeadlineSec)
    process.running = true
  }

  function refresh() {
    if (process.running) return
    if (!sshAvailable && !sshProbeProcess.running) sshProbeProcess.running = true
    if (!sshAvailable && !httpsAvailable) {
      if (!tokenProbeProcess.running) tokenProbeProcess.running = true
      return
    }
    refreshing = true
    runArgs(["ls", "--json"], "list", "", "", false)
  }

  function applyList(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      var records = Array.isArray(parsed) ? parsed : (Array.isArray(parsed.vms) ? parsed.vms : [])
      vms = records.map(function(vm) {
        return {
          vm_name: String(vm.vm_name || vm.name || "Unnamed VM"),
          status: String(vm.status || "unknown"),
          region_display: String(vm.region_display || vm.region || ""),
          ssh_dest: String(vm.ssh_dest || ""),
          https_url: String(vm.https_url || ""),
          shelley_url: String(vm.shelley_url || ""),
          emoji: String(vm.emoji || ""),
          public_proxy: vm.proxy_share === "public" || Boolean(vm.sharing && vm.sharing.public_proxy)
        }
      })
      lastError = ""
    } catch (error) {
      lastError = "exe.dev returned invalid JSON: " + compact(error, "parse failed")
    }
  }

  function applyFailure(exitCode, raw) {
    var rawMessage = compact(raw, "Could not reach exe.dev.")
    var message = friendlyFailure(operation, raw)
    var lower = rawMessage.toLowerCase()
    if (activeTransport === "https") {
      httpsAvailable = !(exitCode === 77 || lower.indexOf("401") !== -1 || lower.indexOf("invalid token") !== -1 || lower.indexOf("unauthorized") !== -1)
    }
    updateConnectionState()
    lastError = (needsAuth || operation === "create") ? "" : message
    operationFailed(operation, message)
  }

  function openSetup() {
    Qt.openUrlExternally("https://exe.dev/user")
  }

  function openSshSetup() {
    Quickshell.execDetached(["omarchy-launch-terminal", "bash", "-lc", "printf '\\nConnect this machine to exe.dev, then close the terminal.\\n\\n'; ssh exe.dev; omarchy-shell sco.omexe open"])
  }

  function openSignIn() { Qt.openUrlExternally("https://exe.dev/auth") }
  function openDashboard(vm) { if (vm && vm.vm_name) Qt.openUrlExternally("https://exe.dev/vm/" + encodeURIComponent(String(vm.vm_name))) }
  function openTerminal(vm) { if (vm && vm.ssh_dest) Quickshell.execDetached(["omarchy-launch-terminal", "ssh", String(vm.ssh_dest)]) }
  function openLobby() { Quickshell.execDetached(["omarchy-launch-terminal", "ssh", "exe.dev"]) }
  function openHttps(vm) { if (vm && vm.https_url) Qt.openUrlExternally(String(vm.https_url)); else lastError = "This machine has no HTTPS URL." }
  function openShelley(vm) { if (vm && vm.shelley_url) Qt.openUrlExternally(String(vm.shelley_url)); else lastError = "Shelley is not available on this machine." }

  function restartVm(vm) {
    if (vm && vm.vm_name) runArgs(["restart", String(vm.vm_name), "--json"], "action", "Restarting " + vm.vm_name + "…", "Restarted " + vm.vm_name, true)
  }

  function copyVm(vm, name) {
    if (!vm || !vm.vm_name) return
    var args = ["cp", String(vm.vm_name)]
    var copyName = String(name || "").trim()
    if (copyName) args.push(copyName)
    args.push("--json")
    runArgs(args, "copy", "Copying " + vm.vm_name + "…", "Copied " + vm.vm_name, true)
  }

  function deleteVm(vm) {
    if (!vm || !vm.vm_name) return
    targetVmName = String(vm.vm_name)
    runArgs(["rm", targetVmName, "--json"], "delete", "Deleting " + targetVmName + "…", "Deleted " + targetVmName, true)
  }

  function createVm(name, prompt) {
    var args = ["new", "--json"]
    var vmName = String(name || "").trim()
    var vmPrompt = String(prompt || "").trim()
    if (vmName) args.push("--name=" + vmName)
    pendingCreatePrompt = vmPrompt
    targetVmName = vmName
    return runArgs(args, "create", "Creating " + (vmName || "machine") + "…", "Created " + (vmName || "machine"), true)
  }

  function startShelleyPrompt(vm, prompt) {
    if (!vm || !vm.vm_name || !prompt || shelleyPromptProcess.running) return false
    var transport = sshAvailable ? "ssh" : (httpsAvailable ? "https" : "")
    if (!transport) return false
    shelleyPromptVmName = String(vm.vm_name)
    shelleyPromptStatus = "Starting Shelley with your prompt…"
    shelleyOutputBuffer = ""
    shelleyErrorBuffer = ""
    shelleyPromptRunning = true
    shelleyPromptProcess.command = commandFor(transport, ["shelley", "prompt", shelleyPromptVmName, String(prompt)], shelleyDeadlineSec)
    shelleyPromptProcess.running = true
    return true
  }

  function setVmPublic(vm, makePublic) {
    if (!vm || !vm.vm_name) return
    targetVmName = String(vm.vm_name)
    targetPublic = Boolean(makePublic)
    runArgs(["share", makePublic ? "set-public" : "set-private", targetVmName], "visibility",
      "Making " + targetVmName + (makePublic ? " public…" : " private…"),
      targetVmName + " is now " + (makePublic ? "public" : "private"), true)
  }

  function updateVisibility(vmName, makePublic) {
    vms = vms.map(function(vm) {
      if (vm.vm_name !== vmName) return vm
      var updated = Object.assign({}, vm)
      updated.public_proxy = makePublic
      return updated
    })
  }

  function copyPublicUrl(vmName) {
    var name = String(vmName || "")
    if (!name) return
    var vm = vms.find(function(candidate) { return candidate.vm_name === name })
    var url = vm && vm.https_url ? String(vm.https_url) : ("https://" + name + ".exe.xyz")
    var script = "printf %s " + Util.shellQuote(url)
      + " | wl-copy && notify-send --app-name=omexe "
      + Util.shellQuote("Public URL copied") + " " + Util.shellQuote(url)
    Quickshell.execDetached(["bash", "-c", script])
  }

  function createdVmFrom(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      var vm = parsed.vm || parsed
      var name = String(vm.vm_name || vm.name || targetVmName || "")
      if (!name) return null
      return {
        vm_name: name,
        ssh_dest: String(vm.ssh_dest || (name + ".exe.xyz")),
        https_url: String(vm.https_url || ("https://" + name + ".exe.xyz")),
        shelley_url: String(vm.shelley_url || ("https://" + name + ".shelley.exe.xyz"))
      }
    } catch (error) {
      return targetVmName ? { vm_name: targetVmName, ssh_dest: targetVmName + ".exe.xyz" } : null
    }
  }

  function showStatus(message) {
    actionStatus = message
    statusTimer.restart()
  }

  Timer {
    interval: Math.max(5, root.refreshIntervalSec) * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 30000
    repeat: true
    running: !root.sshAvailable
    onTriggered: if (!sshProbeProcess.running) sshProbeProcess.running = true
  }

  Process {
    id: sshProbeProcess
    running: true
    command: root.sshCommand(["whoami", "--json"], root.probeDeadlineSec)
    stdout: StdioCollector { id: sshProbeOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.sshAvailable = exitCode === 0
      if (root.sshAvailable) root.recordIdentity(sshProbeOutput.text)
      root.connectionChecking = tokenProbeProcess.running
      root.updateConnectionState()
      if (root.sshAvailable) root.refresh()
    }
  }

  Process {
    id: tokenProbeProcess
    running: true
    command: root.httpsCommand(["whoami", "--json"], root.probeDeadlineSec)
    stdout: StdioCollector { id: tokenProbeOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.httpsAvailable = exitCode === 0
      if (root.httpsAvailable && !root.username) root.recordIdentity(tokenProbeOutput.text)
      root.connectionChecking = sshProbeProcess.running
      root.updateConnectionState()
      if (!root.sshAvailable && root.httpsAvailable) root.refresh()
    }
  }

  Process {
    id: fallbackProvisionProcess
    running: false
    command: {
      var lifetime = Math.max(1, Math.min(365, parseInt(String(root.tokenLifetimeDays), 10) || 90))
      var removeCommand = Util.shellQuote("ssh-key remove omexe")
      var mintCommand = Util.shellQuote("ssh-key generate-api-key --label=omexe '--cmds=ls,new,cp,rm,restart,whoami,share show,share set-public,share set-private,shelley prompt' --exp=" + lifetime + "d")
      var script = "set -e -o pipefail; /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 exe.dev " + removeCommand + " >/dev/null 2>&1 || true; token=$(/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 exe.dev " + mintCommand + " | /usr/bin/head -c " + root.remoteStdoutLimitBytes + " | /usr/bin/grep -oE 'exe[01]\\.[A-Za-z0-9._-]+' | /usr/bin/tail -1); [ -n \"$token\" ]; printf %s \"$token\" | secret-tool store --label='exe.dev Omexe plugin' service exe.dev application sco.omexe"
      return root.boundedCommand(["/usr/bin/env", "-u", "BASH_ENV", "PATH=/usr/local/bin:/usr/bin:/bin", "/usr/bin/bash", "--noprofile", "--norc", "-p", "-c", script], 30)
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && !tokenProbeProcess.running) tokenProbeProcess.running = true
    }
  }

  Timer { id: delayedRefresh; interval: 900; repeat: false; onTriggered: root.refresh() }
  Timer { id: statusTimer; interval: 2400; repeat: false; onTriggered: root.actionStatus = "" }

  Process {
    id: shelleyPromptProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        root.shelleyOutputBuffer = root.appendCapped(root.shelleyOutputBuffer, String(line) + "\n", root.remoteStdoutLimitBytes)
        if (String(line).trim() !== "") root.shelleyPromptStatus = root.compact(line, root.shelleyPromptStatus)
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        root.shelleyErrorBuffer = root.appendCapped(root.shelleyErrorBuffer, String(line) + "\n", root.remoteStderrLimitBytes)
        if (String(line).trim() !== "") root.shelleyPromptStatus = root.compact(line, root.shelleyPromptStatus)
      }
    }
    onExited: function(exitCode) {
      root.shelleyPromptRunning = false
      if (exitCode === 0) {
        root.shelleyPromptStatus = "Prompt sent — open Shelley to follow along"
        root.showStatus("Prompt sent to Shelley")
      } else {
        root.shelleyPromptStatus = "Prompt delivery uncertain — open Shelley to check before retrying"
        root.lastError = root.friendlyFailure("shelley", root.shelleyOutputBuffer || root.shelleyErrorBuffer)
      }
    }
  }

  Process {
    id: process
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        root.outputBuffer = root.appendCapped(root.outputBuffer, String(line) + "\n", root.remoteStdoutLimitBytes)
        if (root.operation === "create" && String(line).trim() !== "" && String(line).trim().charAt(0) !== "{")
          root.creationProgress = root.compact(line, root.creationProgress)
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        root.errorBuffer = root.appendCapped(root.errorBuffer, String(line) + "\n", root.remoteStderrLimitBytes)
        if (root.operation === "create" && String(line).trim() !== "") root.creationProgress = root.compact(line, root.creationProgress)
      }
    }
    onExited: function(exitCode) {
      var currentOperation = root.operation
      var output = root.outputBuffer.trim()
      var error = root.errorBuffer.trim()
      root.refreshing = false
      root.actionStatus = ""

      var boundedFailure = exitCode === 98 || exitCode === 99 || exitCode === 124 || exitCode === 137
        || (root.activeTransport === "https" && [18, 28, 52, 55, 56, 63].indexOf(exitCode) !== -1)
      if (root.operationMutation && boundedFailure) {
        var uncertain = "The request was interrupted or exceeded its output or time limit. Refresh before retrying so this action is not duplicated."
        root.lastError = currentOperation === "create" ? "" : uncertain
        root.operationFailed(currentOperation, uncertain)
        return
      }

      if (exitCode === 255 && root.activeTransport === "ssh") {
        root.sshAvailable = false
        root.updateConnectionState()
        if (!root.operationMutation && root.httpsAvailable) {
          root.retryReadOverHttps()
          return
        }
        if (root.operationMutation) {
          var interrupted = "SSH was interrupted. Refresh before retrying so this action is not duplicated."
          root.lastError = currentOperation === "create" ? "" : interrupted
          root.operationFailed(currentOperation, interrupted)
          return
        }
      }

      if (exitCode !== 0) {
        root.applyFailure(exitCode, output || error)
      } else if (currentOperation === "list") {
        root.applyList(output)
      } else {
        root.lastError = ""
        if (currentOperation === "visibility") {
          root.updateVisibility(root.targetVmName, root.targetPublic)
          if (root.targetPublic) root.copyPublicUrl(root.targetVmName)
        }
        if (currentOperation === "delete") root.vms = root.vms.filter(function(vm) { return vm.vm_name !== root.targetVmName })
        if (currentOperation === "create") {
          var created = root.createdVmFrom(output)
          if (created) {
            var prompt = root.pendingCreatePrompt
            root.pendingCreatePrompt = ""
            var record = Object.assign({
              status: "running",
              region_display: "",
              emoji: "",
              public_proxy: false
            }, created)
            root.vms = [record].concat(root.vms.filter(function(vm) { return vm.vm_name !== record.vm_name }))
            root.vmCreated(record, prompt !== "")
            if (prompt !== "") root.startShelleyPrompt(record, prompt)
          }
        }
        root.showStatus(root.successMessage)
        delayedRefresh.restart()
      }
    }
  }
}
