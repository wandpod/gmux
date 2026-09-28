# gmux

Stream multiplexer: runs terminals, serial ports, sockets and VNC sessions
behind one process, routes data between them and serves a web dashboard.

This repository hosts the gmux releases, the installer and the Nix flake. The
source code is not public. gmux is free to use, including commercially; see
[LICENSE](https://github.com/wandpod/gmux/blob/main/LICENSE) and
[THIRD_PARTY_NOTICES](https://github.com/wandpod/gmux/blob/main/THIRD_PARTY_NOTICES).

## Install

Linux and macOS:

```bash
curl -fsSL https://get.wandpod.com/gmux | sh
```

The installer puts `gmux` in `/usr/local/bin` (override with
`GMUX_INSTALL_DIR`, e.g. `$HOME/.local/bin`), the agent bundle in
`<prefix>/lib/gmux/agent-binaries`, and shell completion for Bash, Zsh, Fish,
Nushell and PowerShell. `GMUX_VERSION=0.1.161` pins a version.
`gmux upgrade` installs the latest release later.

Direct downloads (Windows, `.deb`, Arch `PKGBUILD`) are on the
[releases page](https://github.com/wandpod/gmux/releases). Stable links:

```text
https://get.wandpod.com/gmux/latest/gmux-linux-amd64.tar.gz
https://get.wandpod.com/gmux/<version>/gmux-linux-amd64.tar.gz
```

Container image: `ghcr.io/wandpod/gmux:latest` (entrypoint `gmux`).

## Nix

```bash
nix run github:wandpod/gmux -- --version
nix profile add github:wandpod/gmux
nix profile upgrade gmux
```

Under Nix, `gmux upgrade` refuses and the startup update check is off: Nix owns
upgrades. gmux is unfree; this flake's own packages already allow it. When you
use `overlays.default` in your own nixpkgs, allow it there:

```nix
nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "gmux";
```

NixOS module (a hub and/or an agent linked to a central):

```nix
# flake inputs: gmux.url = "github:wandpod/gmux";
{ inputs, ... }: {
  imports = [ inputs.gmux.nixosModules.default ];

  services.gmux.serve = {
    enable = true;
    web = "127.0.0.1:8088";
    settings.users = [ { name = "alice"; admin = true; tokens = [ "\${ALICE_TOKEN}" ]; } ];
    environmentFile = "/run/secrets/gmux.env";
  };

  services.gmux.agent = {
    enable = true;
    url = "wss://gmux.example.com/api/agent/ws";
    tokenFile = "/run/secrets/gmux-agent-token";
  };
}
```

State lives in `/var/lib/gmux` and `/var/lib/gmux-agent`; each unit has a
private control socket under `/run/gmux` or `/run/gmux-agent` (reach it with
`GMUX_SOCKET_DIR`).

## Issues

Bug reports and questions are welcome in
[issues](https://github.com/wandpod/gmux/issues).
