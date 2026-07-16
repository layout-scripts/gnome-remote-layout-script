# gnome-remote-layout-script

`setup-gnome-remote.sh` turns a headless Debian, Ubuntu, or other Debian-based server into a machine reachable as a full GNOME remote desktop over [Tailscale](https://tailscale.com/) — with audio, USB-over-IP, and WebAuthn/FIDO2 packages prepared. Nothing here changes how the machine boots: there is **no display manager and no graphical login**. GNOME only starts on demand, the moment an RDP client connects, and shuts back down afterwards.

## Languages

- English (this file)
- [Deutsch](README.de.md)
- [Español](README.es.md)

## What it does

On a Debian (or Debian-based) system with `systemd`, the script offers four independently selectable components (all pre-selected in an interactive `whiptail` checklist, all installed in an automated run):

- **GNOME + RDP, truly headless, on demand**
  - Installs only `gnome-session`, `gnome-shell`, `mutter`, and `gnome-remote-desktop` — deliberately **not** the `ubuntu-desktop`/`ubuntu-desktop-minimal` meta-packages, since those pull in `gdm3` and typically switch the system to `graphical.target` on install.
  - Records `systemctl get-default` before installing and resets it back if any dependency changed it, so the machine keeps booting to `multi-user.target`.
  - Enables `gnome-remote-desktop`'s **system-wide headless mode** (`gnome-remote-desktop.service`): a GNOME session is spun up automatically only when an RDP client connects, and torn down again afterwards — no idle resource usage.
  - Generates a self-signed TLS certificate for RDP if none exists yet, configures it via `grdctl --system rdp set-tls-cert/-key`, and asks interactively for RDP credentials (`grdctl --system rdp set-credentials`) — credentials are only ever passed to `grdctl`, never stored by the script itself.
  - Restricts RDP (port 3389) via `ufw` to the `tailscale0` interface only.
- **Audio (PipeWire)**: installs `pipewire`, `pipewire-pulse`, `wireplumber`, and enables them `--global` so audio is active even in the on-demand session started by headless RDP, without anyone having logged in interactively first.
- **USB-over-IP (usbip)**: installs `usbip` and the kernel-matching `linux-tools-<kernel>` package, loads the `usbip-core`/`usbip_host`/`vhci-hcd` kernel modules persistently, writes a small `usbipd.service` unit (Ubuntu ships no ready-made one), and restricts port 3240 to `tailscale0` via `ufw`.
- **WebAuthn/FIDO2 (preparation only)**: installs `libfido2-1`, `libpam-u2f`, `fido2-tools`. PAM itself is **not** touched automatically — enabling a security key for login is a deliberate manual step (`pamu2fcfg`, then editing `/etc/pam.d/` by hand), to avoid ever locking yourself out of a headless server.

Before touching the firewall at all, the script always allows SSH first (`ufw allow OpenSSH`), so a remote session can never lock itself out.

Tailscale itself is installed via the official `https://tailscale.com/install.sh` script if missing; if it isn't authenticated yet, the script prints a reminder to run `sudo tailscale up` and continues once you have.

## Requirements

- Debian or Debian-based system using `apt` and `systemd`.
- Run the script as **root**.
- Outbound internet access (Tailscale install script, apt packages).

## Usage

1. Clone this repository:

   ```bash
   git clone https://github.com/layout-scripts/gnome-remote-layout-script.git
   cd gnome-remote-layout-script
   ```

2. Make the script executable and run it:

   ```bash
   chmod +x setup-gnome-remote.sh
   sudo ./setup-gnome-remote.sh
   ```

3. If prompted, authenticate Tailscale (`sudo tailscale up`) and re-run the script.

4. Verify:

   ```bash
   systemctl get-default                 # should stay multi-user.target
   systemctl status gnome-remote-desktop tailscaled usbipd
   ufw status verbose                    # RDP/usbip only on tailscale0
   tailscale ip -4
   ```

5. From another device on the same tailnet, connect an RDP client to `<tailscale-ip>:3389` — a GNOME session should start automatically, with audio over the RDP channel.

## License

This project is licensed under the **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.

See the `LICENSE` file for full details.
