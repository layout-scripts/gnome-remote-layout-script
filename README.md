# gnome-remote-layout-script

`setup-gnome-remote.sh` turns a Debian, Ubuntu, or other Debian-based server into a usable GNOME remote workstation through GNOME Remote Desktop/RDP. Besides [Tailscale](https://tailscale.com/), it can prepare SSH tunnels and WireGuard; audio, microphone, file access, USB-over-IP, webcam options, and WebAuthn/FIDO2 packages are selectable.

## Languages

- English (this file)
- [Deutsch](README.de.md)
- [Español](README.es.md)

## What it does

On a Debian (or Debian-based) system with `systemd`, the script offers selectable components, desktop profiles, webcam options, and private transports. If GNOME + RDP is selected, it also asks for the GNOME-RDP mode:

- **GNOME + RDP**
  - **Single-user headless**: installs `gnome-session`, `gnome-shell`, `mutter`, and `gnome-remote-desktop`, enables `loginctl enable-linger` for a selected Linux user, and starts that user's `gnome-remote-desktop-headless.service`. The server keeps its previous default target, usually `multi-user.target`; no GDM is required.
  - **GDM remote login**: also installs `gdm3`, switches to `graphical.target`, and enables the system-wide GNOME remote login path. This is closer to a GNOME login screen, but intentionally brings in a display manager.
  - Generates a self-signed TLS certificate for RDP if none exists yet, configures it with `grdctl`, and asks interactively for RDP credentials — credentials are only ever passed to `grdctl`, never stored by the script itself.
  - Restricts RDP (port 3389) via `ufw` to selected private interfaces; with SSH tunnel mode, RDP is not opened directly.
- **Desktop baseline**: default profile `workstation` installs a curated GNOME base with terminal, Files, Settings, portals, GVFS/FUSE/backends, keyring, fonts, system tools, and file access. `minimal` skips these extras; `ubuntu-desktop-minimal` is intended for Ubuntu only.
- **File exchange**: installs portals and GVFS backends for clipboard/portal and file access in the remote session. It does not automatically expose a public file server.
- **Audio (PipeWire)**: installs PipeWire including Pulse/ALSA, WirePlumber, GStreamer/PipeWire, and portal basics so speaker output and microphone input are prepared for GNOME RDP.
- **USB-over-IP (usbip)**: installs the `linux-tools-<kernel>` package matching the running kernel, with Ubuntu HWE fallbacks, loads `usbip-core`/`usbip_host`/`vhci-hcd`, writes `usbipd.service`, and restricts port 3240 to private transports.
- **Webcam**: `usbip-webcam` prepares physical USB webcams via USB-over-IP plus camera test tools. Optional `virtual-webcam` also installs `v4l2loopback`, `ffmpeg`, `pipewire-v4l2`, and V4L2 tools. Native webcam forwarding through GNOME RDP is not assumed to be reliable.
- **Transports**:
  - **Tailscale**: installs/enables Tailscale and allows RDP/usbip on `tailscale0`.
  - **SSH tunnel**: installs/enables OpenSSH, allows SSH only, and prints local port-forwarding commands for RDP and optional usbip.
  - **WireGuard**: installs WireGuard tools. A tunnel is only enabled when `GNOME_REMOTE_WIREGUARD_CONFIG=/path/wg0.conf` is set; otherwise the prerequisites are installed only.
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

   Important environment options:

   ```bash
   GNOME_REMOTE_COMPONENTS=desktop-baseline,gnome-rdp,audio,usbip,webauthn
   GNOME_REMOTE_DESKTOP_PROFILE=workstation        # workstation|minimal|ubuntu-desktop-minimal
   GNOME_REMOTE_TRANSPORTS=tailscale,ssh-tunnel,wireguard
   GNOME_REMOTE_WEBCAM=usbip,virtual               # usbip|virtual|none, combinable
   GNOME_REMOTE_WIREGUARD_CONFIG=/root/wg0.conf    # optional
   ```

3. If prompted, authenticate Tailscale (`sudo tailscale up`) and re-run the script.

4. Verify:

   ```bash
   systemctl get-default                 # single-user: should stay multi-user.target; GDM: graphical.target
   systemctl status tailscaled usbipd
   ufw status verbose                    # RDP/usbip only over selected private transports
   tailscale ip -4                       # if Tailscale was selected
   wg show                               # if WireGuard is active
   ```

5. From another device, connect an RDP client to `<private-ip>:3389` over Tailscale/WireGuard. For SSH tunnels:

   ```bash
   ssh -L 3389:127.0.0.1:3389 <user>@<server>
   # with usbip too:
   ssh -L 3389:127.0.0.1:3389 -L 3240:127.0.0.1:3240 <user>@<server>
   ```

   Then point the RDP client at `localhost:3389`.

## License

This project is licensed under the **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.

See the `LICENSE` file for full details.
