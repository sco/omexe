# omexe (exe for omarchy)

A compact, keyboard-first [Omarchy](https://omarchy.org) bar plugin for working with [Exe](https://exe.dev) VMs.

![omexe preview](https://omexe.dev/preview.png)

[Watch the video](https://youtu.be/LO7UsEX0iOI)

## Features

- List and open your VMs
- Launch a terminal, browser, or Shelley for any VM
- Restart, copy, delete, and change VM sharing
- Create a VM with an optional Shelley prompt


## Requirements

Authenticate your Omarchy machine with Exe by running:

```bash
ssh exe.dev
```

If needed, generate an SSH key and follow the sign-in prompt. Running the command again opens the Exe lobby.


## Installation

```bash
omarchy plugin add https://github.com/sco/omexe.git --enable
```

The `--enable` flag activates the plugin immediately after installation. Plugins run unsandboxed inside the Omarchy shell, so review the source before enabling it.


## First use

Omexe uses `ssh exe.dev` first. If the machine is not connected, the panel provides profile and terminal setup actions. Once SSH succeeds, Omexe creates a scoped HTTPS fallback token in GNOME Keyring. Read-only commands may fail over transparently; mutations are not retried after an ambiguous SSH interruption.


## Keyboard shortcuts

With the panel open:

- up/down or `j`/`k`: select a VM
- right/left: select action
- `enter`: run the selected action
- `a`: agent (Shelley)
- `b` / `o`: open HTTPS URL
- `.`: toggle action menu
- `p`: public/private share toggle
- `r`: restart VM
- `c`: copy VM
- `n`: new VM
- `f`: refresh the list


## Updating and removal

```bash
omarchy plugin update sco.omexe
omarchy plugin remove sco.omexe
```


## Security

- The plugin runs unsandboxed inside the long-lived Omarchy shell, like every shell plugin.
- It executes `ssh`, `curl`, `secret-tool`, and `omarchy-launch-terminal` as the current user; it never requests elevated privileges or installs software.
- VM names, prompts, and destinations are shell-quoted or passed as discrete process arguments before execution.
- Review updates before accepting them; `omarchy plugin update` displays the incoming diff.


## Documentation

- [exe.dev's full docs](https://exe.dev/llms.txt)
- [Omarchy plugin development guide](https://omarchyplugins.com/develop.html)

This is an independent community plugin. Its source lives at [github.com/sco/omexe](https://github.com/sco/omexe).

For questions, comments, or compliments, contact [@sco](https://x.com/sco) on Twitter.


## License

MIT
