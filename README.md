# gnome-remote-layout-script

`setup-gnome-remote.sh` turns a Debian, Ubuntu, or other Debian-based server into a machine reachable through GNOME Remote Desktop/RDP over [Tailscale](https://tailscale.com/) — with audio, USB-over-IP, and WebAuthn/FIDO2 packages prepared. During installation, you choose between a single-user headless mode without a display manager and a GDM remote login mode.

## Languages

- English (this file)
- [Deutsch](README.de.md)
- [Español](README.es.md)

## What it does

On a Debian (or Debian-based) system with `systemd`, the script offers four independently selectable components (all pre-selected in an interactive `whiptail` checklist, all installed in an automated run). If GNOME + RDP is selected, it also asks for the GNOME-RDP mode:

- **GNOME + RDP**
  - **Single-user headless**: installs `gnome-session`, `gnome-shell`, `mutter`, and `gnome-remote-desktop`, enables `loginctl enable-linger` for a selected Linux user, and starts that user's `gnome-remote-desktop-headless.service`. The server keeps its previous default target, usually `multi-user.target`; no GDM is required.
  - **GDM remote login**: also installs `gdm3`, switches to `graphical.target`, and enables the system-wide GNOME remote login path. This is closer to a GNOME login screen, but intentionally brings in a display manager.
  - Generates a self-signed TLS certificate for RDP if none exists yet, configures it with `grdctl`, and asks interactively for RDP credentials — credentials are only ever passed to `grdctl`, never stored by the script itself.
  - Restricts RDP (port 3389) via `ufw` to the `tailscale0` interface only.
- **Audio (PipeWire)**: installs `pipewire`, `pipewire-pulse`, `wireplumber`, and enables them `--global` so audio is active even in the on-demand session started by headless RDP, without anyone having logged in interactively first.
- **USB-over-IP (usbip)**: installs `usbip` and the kernel-matching `linux-tools-<kernel>` package, loads the `usbip-core`/`usbip_host`/`vhci-hcd` kernel modules persistently, writes a small `usbipd.service` unit (Ubuntu ships no ready-made one), and restricts port 3240 to `tailscale0` via `ufw`.
- **WebAuthn/FIDO2 (preparation only)**: installs `libfido2-1`, `libpam-u2f`, `fido2-tools`. PAM itself is **not** touched automatically — enabling a security key for login is a deliberate manual step (`pamu2fcfg`, then editing `/etc/pam.d/` by hand), to avoid ever locking yourself out of a headless server.

Before touching the firewall at all, the script always allows SSH first (`ufw allow OpenSSH`), so a remote session can never lock itself out.

Tailscale itself is installed via the official `https://tailscale.com/install.sh` script if missing; if it isn't authenticated yet, the script prints a reminder to run `sudo tailscale up` and continues once you have.

GNOME Remote Desktop does not guarantee that a GUI session keeps running after a network disconnect and can later be reattached. Use `systemd`, `tmux`, or another non-GUI mechanism for long-running jobs.

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

   For automated runs without a terminal:

   ```bash
   sudo LAYOUT_SCRIPT_ASSUME_YES=1 GNOME_REMOTE_MODE=single-user-headless GNOME_REMOTE_USER=<linux-user> ./setup-gnome-remote.sh
   # or:
   sudo LAYOUT_SCRIPT_ASSUME_YES=1 GNOME_REMOTE_MODE=gdm-remote-login ./setup-gnome-remote.sh
   ```

3. If prompted, authenticate Tailscale (`sudo tailscale up`) and re-run the script.

4. Verify:

   ```bash
   systemctl get-default                 # single-user: should stay multi-user.target; GDM: graphical.target
   systemctl status tailscaled usbipd
   ufw status verbose                    # RDP/usbip only on tailscale0
   tailscale ip -4
   ```

5. From another device on the same tailnet, connect an RDP client to `<tailscale-ip>:3389` — depending on the selected mode, the connection lands in the single-user headless session or in GDM remote login.

## License

This project is licensed under the **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.

See the `LICENSE` file for full details.
