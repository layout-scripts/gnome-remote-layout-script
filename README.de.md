# gnome-remote-layout-script

`setup-gnome-remote.sh` macht aus einem headless Debian-, Ubuntu- oder anderen Debian-basierten Server eine Maschine, die über [Tailscale](https://tailscale.com/) als vollwertiger GNOME-Remote-Desktop erreichbar ist — mit Audio, USB-over-IP und vorbereiteten WebAuthn/FIDO2-Paketen. Am Bootverhalten ändert sich dabei nichts: Es gibt **keinen Display-Manager und keine grafische Anmeldung**. GNOME startet ausschließlich on-demand, sobald ein RDP-Client sich verbindet, und fährt danach wieder herunter.

## Sprachen

- [English](README.md)
- Deutsch (diese Datei)
- [Español](README.es.md)

## Was das Skript tut

Auf einem Debian(-basierten) System mit `systemd` bietet das Skript vier unabhängig wählbare Komponenten an (alle in einem interaktiven `whiptail`-Auswahldialog vorausgewählt, in einem automatisierten Lauf werden alle installiert):

- **GNOME + RDP, echt headless, on-demand**
  - Installiert nur `gnome-session`, `gnome-shell`, `mutter` und `gnome-remote-desktop` — bewusst **nicht** die Metapakete `ubuntu-desktop`/`ubuntu-desktop-minimal`, da diese `gdm3` mitziehen und beim Installieren typischerweise auf `graphical.target` umstellen.
  - Merkt sich `systemctl get-default` vor der Installation und setzt es zurück, falls eine Abhängigkeit es verändert hat — die Maschine bootet weiterhin in `multi-user.target`.
  - Aktiviert den **systemweiten Headless-Modus** von `gnome-remote-desktop` (`gnome-remote-desktop.service`): Eine GNOME-Session wird automatisch nur bei einer RDP-Verbindung gestartet und danach wieder beendet — kein Ressourcenverbrauch im Leerlauf.
  - Erzeugt bei Bedarf ein selbstsigniertes TLS-Zertifikat für RDP, konfiguriert es über `grdctl --system rdp set-tls-cert/-key` und fragt interaktiv nach RDP-Zugangsdaten (`grdctl --system rdp set-credentials`) — die Zugangsdaten werden ausschließlich an `grdctl` weitergereicht, nie vom Skript selbst gespeichert.
  - Beschränkt RDP (Port 3389) per `ufw` ausschließlich auf das Interface `tailscale0`.
- **Audio (PipeWire)**: installiert `pipewire`, `pipewire-pulse`, `wireplumber` und aktiviert sie `--global`, damit Audio auch in der on-demand gestarteten Headless-RDP-Session funktioniert, ohne dass sich zuvor jemand interaktiv angemeldet hat.
- **USB-over-IP (usbip)**: installiert `usbip` und das zum Kernel passende `linux-tools-<kernel>`-Paket, lädt die Kernelmodule `usbip-core`/`usbip_host`/`vhci-hcd` dauerhaft, schreibt eine kleine `usbipd.service`-Unit (Ubuntu liefert keine fertige mit) und beschränkt Port 3240 per `ufw` auf `tailscale0`.
- **WebAuthn/FIDO2 (nur Vorbereitung)**: installiert `libfido2-1`, `libpam-u2f`, `fido2-tools`. PAM selbst wird **nicht** automatisch verändert — einen Sicherheitsschlüssel für den Login zu aktivieren ist ein bewusster manueller Schritt (`pamu2fcfg`, danach `/etc/pam.d/` von Hand anpassen), um sich auf einem headless Server niemals versehentlich auszusperren.

Bevor überhaupt an der Firewall etwas verändert wird, erlaubt das Skript immer zuerst SSH (`ufw allow OpenSSH`), damit sich eine Remote-Sitzung niemals selbst aussperren kann.

Tailscale selbst wird bei Bedarf über das offizielle `https://tailscale.com/install.sh`-Skript installiert; ist es noch nicht angemeldet, gibt das Skript einen Hinweis aus, `sudo tailscale up` auszuführen, und macht danach weiter.

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

3. Falls dazu aufgefordert, Tailscale anmelden (`sudo tailscale up`) und das Skript erneut ausführen.

4. Prüfen:

   ```bash
   systemctl get-default                 # sollte multi-user.target bleiben
   systemctl status gnome-remote-desktop tailscaled usbipd
   ufw status verbose                    # RDP/usbip nur auf tailscale0
   tailscale ip -4
   ```

5. Von einem anderen Gerät im selben Tailnet einen RDP-Client mit `<Tailscale-IP>:3389` verbinden — eine GNOME-Session sollte automatisch starten, mit Audio über den RDP-Kanal.

## Lizenz

Dieses Projekt steht unter der **GNU General Public License v3.0 oder später (GPL-3.0-or-later)**.

Details siehe Datei `LICENSE`.
