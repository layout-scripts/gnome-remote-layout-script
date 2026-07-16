# gnome-remote-layout-script

`setup-gnome-remote.sh` macht aus einem Debian-, Ubuntu- oder anderen Debian-basierten Server eine Maschine, die über [Tailscale](https://tailscale.com/) per GNOME Remote Desktop/RDP erreichbar ist — mit Audio, USB-over-IP und vorbereiteten WebAuthn/FIDO2-Paketen. Bei der Installation wählst du zwischen einem Single-User-Headless-Modus ohne Display-Manager und einem GDM-Remote-Login-Modus.

## Sprachen

- [English](README.md)
- Deutsch (diese Datei)
- [Español](README.es.md)

## Was das Skript tut

Auf einem Debian(-basierten) System mit `systemd` bietet das Skript vier unabhängig wählbare Komponenten an (alle in einem interaktiven `whiptail`-Auswahldialog vorausgewählt, in einem automatisierten Lauf werden alle installiert). Wenn GNOME + RDP ausgewählt ist, fragt es zusätzlich den GNOME-RDP-Modus ab:

- **GNOME + RDP**
  - **Single-User-Headless**: installiert `gnome-session`, `gnome-shell`, `mutter` und `gnome-remote-desktop`, aktiviert `loginctl enable-linger` für einen ausgewählten Linux-Benutzer und startet dessen `gnome-remote-desktop-headless.service`. Der Server bleibt bei seinem bisherigen Default-Target, typischerweise `multi-user.target`; es wird kein GDM benötigt.
  - **GDM Remote Login**: installiert zusätzlich `gdm3`, stellt auf `graphical.target` und aktiviert den systemweiten GNOME-Remote-Login-Pfad. Das ist näher am GNOME-Anmeldebildschirm, bringt aber bewusst einen Display-Manager mit.
  - Erzeugt bei Bedarf ein selbstsigniertes TLS-Zertifikat für RDP, konfiguriert es über `grdctl` und fragt interaktiv nach RDP-Zugangsdaten — die Zugangsdaten werden ausschließlich an `grdctl` weitergereicht, nie vom Skript selbst gespeichert.
  - Beschränkt RDP (Port 3389) per `ufw` ausschließlich auf das Interface `tailscale0`.
- **Audio (PipeWire)**: installiert `pipewire`, `pipewire-pulse`, `wireplumber` und aktiviert sie `--global`, damit Audio auch in der on-demand gestarteten Headless-RDP-Session funktioniert, ohne dass sich zuvor jemand interaktiv angemeldet hat.
- **USB-over-IP (usbip)**: installiert `usbip` und das zum Kernel passende `linux-tools-<kernel>`-Paket, lädt die Kernelmodule `usbip-core`/`usbip_host`/`vhci-hcd` dauerhaft, schreibt eine kleine `usbipd.service`-Unit (Ubuntu liefert keine fertige mit) und beschränkt Port 3240 per `ufw` auf `tailscale0`.
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

3. Falls dazu aufgefordert, Tailscale anmelden (`sudo tailscale up`) und das Skript erneut ausführen.

4. Prüfen:

   ```bash
   systemctl get-default                 # single-user: sollte multi-user.target bleiben; GDM: graphical.target
   systemctl status tailscaled usbipd
   ufw status verbose                    # RDP/usbip nur auf tailscale0
   tailscale ip -4
   ```

5. Von einem anderen Gerät im selben Tailnet einen RDP-Client mit `<Tailscale-IP>:3389` verbinden — je nach gewähltem Modus landet die Verbindung in der Single-User-Headless-Session oder im GDM-Remote-Login.

## Lizenz

Dieses Projekt steht unter der **GNU General Public License v3.0 oder später (GPL-3.0-or-later)**.

Details siehe Datei `LICENSE`.
