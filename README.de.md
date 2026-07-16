# gnome-remote-layout-script

`setup-gnome-remote.sh` macht aus einem Debian-, Ubuntu- oder anderen Debian-basierten Server eine nutzbare GNOME-Remote-Workstation per GNOME Remote Desktop/RDP. Neben Tailscale können SSH-Tunnel und WireGuard vorbereitet werden; Audio, Mikrofon, Datei-Zugriff, USB-over-IP, Webcam-Optionen und WebAuthn/FIDO2-Pakete sind auswählbar.

## Sprachen

- [English](README.md)
- Deutsch (diese Datei)
- [Español](README.es.md)

## Was das Skript tut

Auf einem Debian(-basierten) System mit `systemd` bietet das Skript unabhängig wählbare Komponenten, Desktop-Profile, Webcam-Optionen und private Transportwege an. Wenn GNOME + RDP ausgewählt ist, fragt es zusätzlich den GNOME-RDP-Modus ab:

- **GNOME + RDP**
  - **Single-User-Headless**: installiert `gnome-session`, `gnome-shell`, `mutter` und `gnome-remote-desktop`, aktiviert `loginctl enable-linger` für einen ausgewählten Linux-Benutzer und startet dessen `gnome-remote-desktop-headless.service`. Der Server bleibt bei seinem bisherigen Default-Target, typischerweise `multi-user.target`; es wird kein GDM benötigt.
  - **GDM Remote Login**: installiert zusätzlich `gdm3`, stellt auf `graphical.target` und aktiviert den systemweiten GNOME-Remote-Login-Pfad. Das ist näher am GNOME-Anmeldebildschirm, bringt aber bewusst einen Display-Manager mit.
  - Erzeugt bei Bedarf ein selbstsigniertes TLS-Zertifikat für RDP, konfiguriert es über `grdctl` und fragt interaktiv nach RDP-Zugangsdaten — die Zugangsdaten werden ausschließlich an `grdctl` weitergereicht, nie vom Skript selbst gespeichert.
  - Beschränkt RDP (Port 3389) per `ufw` auf die ausgewählten privaten Interfaces; bei SSH-Tunnel wird RDP nicht direkt geöffnet.
- **Desktop-Basis**: Standard ist `workstation`, eine kuratierte GNOME-Grundausstattung mit Terminal, Dateien, Einstellungen, Portals, GVFS/FUSE/Backends, Keyring, Fonts, Systemwerkzeugen und Datei-Zugriff. `minimal` lässt diese Zusatzpakete weg; `ubuntu-desktop-minimal` ist nur auf Ubuntu vorgesehen.
- **Datei-Austausch**: installiert Portals und GVFS-Backends für Clipboard-/Portal- und Dateizugriff in der Remote-Session. Es wird kein öffentlicher Dateiserver automatisch aktiviert.
- **Audio (PipeWire)**: installiert PipeWire inklusive Pulse/ALSA, WirePlumber, GStreamer/PipeWire und Portal-Grundlagen, damit Lautsprecher und Mikrofon in GNOME RDP vorbereitet sind.
- **USB-over-IP (usbip)**: installiert das zum laufenden Kernel passende `linux-tools-<kernel>`-Paket, mit Ubuntu-HWE-Fallbacks, lädt `usbip-core`/`usbip_host`/`vhci-hcd`, schreibt `usbipd.service` und beschränkt Port 3240 auf private Transporte.
- **Webcam**: `usbip-webcam` bereitet physische USB-Webcams über USB-over-IP samt Kamera-Testtools vor. Optional kann `virtual-webcam` zusätzlich `v4l2loopback`, `ffmpeg`, `pipewire-v4l2` und V4L2-Tools installieren. Native Webcam-Weiterleitung direkt über GNOME RDP wird nicht als verlässlich vorausgesetzt.
- **Transporte**:
  - **Tailscale**: installiert/aktiviert Tailscale und erlaubt RDP/usbip auf `tailscale0`.
  - **SSH-Tunnel**: installiert/aktiviert OpenSSH, erlaubt nur SSH und zeigt lokale Portforwarding-Befehle für RDP und optional usbip.
  - **WireGuard**: installiert WireGuard-Tools. Eine Config wird nur aktiviert, wenn `GNOME_REMOTE_WIREGUARD_CONFIG=/pfad/wg0.conf` gesetzt ist; sonst bleibt es bei installierten Voraussetzungen.
- **WebAuthn/FIDO2 (nur Vorbereitung)**: installiert `libfido2-1`, `libpam-u2f`, `fido2-tools`. PAM selbst wird **nicht** automatisch verändert — einen Sicherheitsschlüssel für den Login zu aktivieren ist ein bewusster manueller Schritt (`pamu2fcfg`, danach `/etc/pam.d/` von Hand anpassen), um sich auf einem headless Server niemals versehentlich auszusperren.

Bevor überhaupt an der Firewall etwas verändert wird, erlaubt das Skript immer zuerst SSH (`ufw allow OpenSSH`), damit sich eine Remote-Sitzung niemals selbst aussperren kann.

Tailscale selbst wird bei Bedarf über das offizielle `https://tailscale.com/install.sh`-Skript installiert; ist es noch nicht angemeldet, gibt das Skript einen Hinweis aus, `sudo tailscale up` auszuführen, und macht danach weiter.

GNOME Remote Desktop garantiert nicht, dass eine GUI-Session nach einem Netzwerkabbruch weiterläuft und später wieder verbunden werden kann. Für lange Jobs sollten `systemd`, `tmux` oder ein anderer nicht-GUI Mechanismus genutzt werden.

## Voraussetzungen

- Debian oder Debian-basiertes System mit `apt` und `systemd`.
- Das Skript als **root** ausführen.
- Ausgehender Internetzugriff (Tailscale-Installationsskript, apt-Pakete).

## Verwendung

1. Repository klonen:

   ```bash
   git clone https://github.com/layout-scripts/gnome-remote-layout-script.git
   cd gnome-remote-layout-script
   ```

2. Skript ausführbar machen und starten:

   ```bash
   chmod +x setup-gnome-remote.sh
   sudo ./setup-gnome-remote.sh
   ```

   Für automatisierte Läufe ohne Terminal:

   ```bash
   sudo LAYOUT_SCRIPT_ASSUME_YES=1 GNOME_REMOTE_MODE=single-user-headless GNOME_REMOTE_USER=<linux-user> ./setup-gnome-remote.sh
   # oder:
   sudo LAYOUT_SCRIPT_ASSUME_YES=1 GNOME_REMOTE_MODE=gdm-remote-login ./setup-gnome-remote.sh
   ```

   Wichtige Env-Optionen:

   ```bash
   GNOME_REMOTE_COMPONENTS=desktop-baseline,gnome-rdp,audio,usbip,webauthn
   GNOME_REMOTE_DESKTOP_PROFILE=workstation        # workstation|minimal|ubuntu-desktop-minimal
   GNOME_REMOTE_TRANSPORTS=tailscale,ssh-tunnel,wireguard
   GNOME_REMOTE_WEBCAM=usbip,virtual               # usbip|virtual|none, kombinierbar
   GNOME_REMOTE_WIREGUARD_CONFIG=/root/wg0.conf    # optional
   ```

3. Falls dazu aufgefordert, Tailscale anmelden (`sudo tailscale up`) und das Skript erneut ausführen.

4. Prüfen:

   ```bash
   systemctl get-default                 # single-user: sollte multi-user.target bleiben; GDM: graphical.target
   systemctl status tailscaled usbipd
   ufw status verbose                    # RDP/usbip nur über gewählte private Transporte
   tailscale ip -4                       # wenn Tailscale gewählt wurde
   wg show                               # wenn WireGuard aktiv ist
   ```

5. Von einem anderen Gerät per Tailscale/WireGuard einen RDP-Client mit `<private-ip>:3389` verbinden. Für SSH-Tunnel:

   ```bash
   ssh -L 3389:127.0.0.1:3389 <user>@<server>
   # mit usbip zusätzlich:
   ssh -L 3389:127.0.0.1:3389 -L 3240:127.0.0.1:3240 <user>@<server>
   ```

   Der RDP-Client verbindet sich danach mit `localhost:3389`.

## Lizenz

Dieses Projekt steht unter der **GNU General Public License v3.0 oder später (GPL-3.0-or-later)**.

Details siehe Datei `LICENSE`.
