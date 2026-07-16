#!/usr/bin/env bash
set -euo pipefail

echo ">>> GNOME-Remote-Setup: headless RDP über Tailscale + Audio + USB-over-IP + WebAuthn-Vorbereitung"

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen." >&2
  exit 1
fi

# --- Abhängigkeiten sicherstellen (Debian/apt) ---
need_pkg() {
  local cmd="$1" pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo ">>> Installiere benötigtes Paket: $pkg"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
  else
    echo ">>> Abhängigkeit $pkg ($cmd) ist bereits vorhanden."
  fi
}

apt_package_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

# --- Ausdrückliche Bestätigung, bevor irgendetwas verändert wird ---
echo
echo "!!! ACHTUNG !!!"
echo "Dieses Skript installiert GNOME-Basispakete (OHNE Display-Manager/gdm3 -"
echo "der Rechner bootet weiterhin in multi-user.target, keine grafische"
echo "Standardanmeldung), richtet gnome-remote-desktop im headless-Modus ein,"
echo "installiert Tailscale, ändert Firewall-Regeln (SSH bleibt zuerst erlaubt)"
echo "und richtet auf Wunsch Audio, USB-over-IP und WebAuthn-Pakete ein."
echo
if [[ -t 0 ]]; then
  read -r -p "Fortfahren? Exakt 'ja' eingeben: " CONFIRM
  if [[ "$CONFIRM" != "ja" ]]; then
    echo "Abgebrochen." >&2
    exit 1
  fi
else
  echo ">>> Kein interaktives Terminal erkannt – Bestätigung übersprungen (automatisierter Lauf)."
fi

# --- Komponentenauswahl (alle vier vorausgewählt, frei abwählbar) ---
declare -a COMPONENTS=(gnome-rdp audio usbip webauthn)
if [[ -t 0 && -t 1 ]]; then
  need_pkg whiptail whiptail
  SELECTED=$(whiptail --title "GNOME-Remote-Komponenten auswählen" \
    --checklist "Alle Komponenten sind vorausgewählt. Leertaste = ab-/anwählen, Enter = bestätigen." \
    18 78 4 \
    "gnome-rdp" "GNOME headless + RDP über Tailscale" ON \
    "audio" "PipeWire/WirePlumber-Audio über RDP" ON \
    "usbip" "USB-over-IP-Server (usbip) über Tailscale" ON \
    "webauthn" "WebAuthn/FIDO2-Pakete vorbereiten (kein PAM-Zwang)" ON \
    3>&1 1>&2 2>&3) || { echo "Abgebrochen." >&2; exit 1; }
  eval "COMPONENTS=($SELECTED)"
else
  echo ">>> Kein interaktives Terminal erkannt – alle vier Komponenten werden eingerichtet."
fi

has_component() {
  local c
  for c in "${COMPONENTS[@]}"; do
    [[ "$c" == "$1" ]] && return 0
  done
  return 1
}

# --- Firewall-Grundlage: ufw, SSH IMMER zuerst erlauben ---
# Reihenfolge ist sicherheitskritisch: SSH muss erlaubt sein, BEVOR ufw
# scharf geschaltet wird, sonst sperrt sich der Nutzer auf einem Remote-
# Server selbst aus.
setup_firewall_base() {
  need_pkg ufw ufw
  echo ">>> Erlaube SSH, bevor die Firewall aktiviert wird"
  ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp
  if ufw status | grep -q "Status: active"; then
    echo ">>> ufw ist bereits aktiv."
  else
    echo ">>> Aktiviere ufw (SSH ist bereits erlaubt)"
    ufw --force enable
  fi
}

TAILSCALE_IFACE="tailscale0"

# --- Tailscale installieren und Interface-Namen bereitstellen ---
setup_tailscale() {
  if ! command -v tailscale >/dev/null 2>&1; then
    echo ">>> Installiere Tailscale über das offizielle Install-Skript"
    curl -fsSL https://tailscale.com/install.sh | sh
  else
    echo ">>> Tailscale ist bereits installiert."
  fi
  systemctl enable --now tailscaled

  if tailscale status >/dev/null 2>&1; then
    echo ">>> Tailscale ist bereits authentifiziert: $(tailscale ip -4 2>/dev/null || echo '<keine IP>')"
  else
    echo "WARNUNG: Tailscale ist noch nicht angemeldet." >&2
    echo "Bitte manuell ausführen und danach dieses Skript erneut starten:" >&2
    echo "    sudo tailscale up" >&2
  fi
}

# --- GNOME + gnome-remote-desktop, echt headless (kein Display-Manager) ---
setup_gnome_rdp() {
  echo ">>> Merke aktuelles Boot-Target (Referenz für die Absicherung unten)"
  local target_before
  target_before=$(systemctl get-default)

  # Bewusst KEINE Metapakete wie ubuntu-desktop/ubuntu-desktop-minimal: die
  # ziehen gdm3 als Abhängigkeit und stellen im Postinst typischerweise
  # automatisch auf graphical.target um. Wir wollen GNOME nur als
  # On-Demand-Session des Headless-RDP-Diensts, keinen grafischen Bootvorgang.
  local pkg
  for pkg in gnome-session gnome-shell mutter gnome-remote-desktop; do
    need_pkg "$pkg" "$pkg"
  done

  local target_after
  target_after=$(systemctl get-default)
  if [[ "$target_after" != "$target_before" ]]; then
    echo "WARNUNG: Ein installiertes Paket hat das Default-Target auf '$target_after' geändert." >&2
    echo ">>> Setze Default-Target zurück auf '$target_before' (kein grafischer Boot gewünscht)."
    systemctl set-default "$target_before"
  fi

  echo ">>> Aktiviere gnome-remote-desktop im systemweiten Headless-Modus"
  grdctl --system rdp enable

  local cert_dir="/etc/gnome-remote-desktop"
  local cert="$cert_dir/rdp-tls.crt" key="$cert_dir/rdp-tls.key"
  if [[ -f "$cert" && -f "$key" ]]; then
    echo ">>> TLS-Zertifikat für RDP existiert bereits, überspringe Erzeugung."
  else
    echo ">>> Erzeuge selbstsigniertes TLS-Zertifikat für RDP"
    mkdir -p "$cert_dir"
    openssl req -new -x509 -days 3650 -nodes -newkey rsa:4096 \
      -keyout "$key" -out "$cert" \
      -subj "/CN=$(hostname -f 2>/dev/null || hostname)"
    chmod 600 "$key"
  fi
  grdctl --system rdp set-tls-cert "$cert"
  grdctl --system rdp set-tls-key "$key"

  if [[ -t 0 ]]; then
    echo ">>> RDP-Zugangsdaten festlegen (werden nur an grdctl übergeben, nicht gespeichert)"
    read -r -p "RDP-Benutzername: " RDP_USER
    read -r -s -p "RDP-Passwort: " RDP_PASS
    echo
    grdctl --system rdp set-credentials "$RDP_USER" "$RDP_PASS"
    unset RDP_PASS
  else
    echo ">>> Kein interaktives Terminal – RDP-Zugangsdaten bitte danach manuell setzen:"
    echo "    sudo grdctl --system rdp set-credentials <Benutzer> <Passwort>"
  fi

  systemctl enable --now gnome-remote-desktop.service

  echo ">>> Beschränke RDP (3389) per ufw auf das Tailscale-Interface ${TAILSCALE_IFACE}"
  ufw allow in on "$TAILSCALE_IFACE" to any port 3389 proto tcp
}

# --- Audio: PipeWire/WirePlumber auch für On-Demand-Sessions aktivieren ---
setup_audio() {
  need_pkg pipewire pipewire
  need_pkg wireplumber wireplumber
  apt_package_available pipewire-pulse && need_pkg pipewire-pulse pipewire-pulse

  # --global aktiviert die User-Units für JEDE zukünftige Session, auch für
  # die vom Headless-RDP-Dienst on-demand erzeugte - ohne dass sich vorher
  # ein Benutzer interaktiv anmelden musste.
  echo ">>> Aktiviere PipeWire/WirePlumber global für alle (auch on-demand) Nutzersessions"
  systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service
}

# --- USB-over-IP: Server-Seite auf node6, Client verbindet über Tailscale ---
setup_usbip() {
  need_pkg usbip linux-tools-generic
  if apt_package_available "linux-tools-$(uname -r)"; then
    need_pkg usbipd "linux-tools-$(uname -r)"
  else
    echo "WARNUNG: linux-tools-$(uname -r) nicht verfügbar – usbip-Binary kommt ggf. nur aus linux-tools-generic." >&2
  fi

  echo ">>> Lade usbip-Kernelmodule dauerhaft"
  cat > /etc/modules-load.d/usbip.conf <<'EOF'
usbip-core
usbip_host
vhci-hcd
EOF
  modprobe usbip-core 2>/dev/null || true
  modprobe usbip_host 2>/dev/null || true
  modprobe vhci-hcd 2>/dev/null || true

  # Ubuntu liefert keinen fertigen systemd-Dienst für usbipd mit - hier
  # analog zu den apt-Hooks im Snapper-Skript selbst geschrieben.
  local unit="/etc/systemd/system/usbipd.service"
  if [[ -f "$unit" ]]; then
    echo ">>> usbipd.service existiert bereits, überspringe."
  else
    echo ">>> Erzeuge usbipd.service"
    cat > "$unit" <<'EOF'
[Unit]
Description=usbip host daemon
After=network.target

[Service]
ExecStart=/usr/sbin/usbipd -D --no-daemon
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
  fi
  systemctl enable --now usbipd.service

  echo ">>> Beschränke usbip (3240) per ufw auf das Tailscale-Interface ${TAILSCALE_IFACE}"
  ufw allow in on "$TAILSCALE_IFACE" to any port 3240 proto tcp

  echo ">>> USB-Geräte auflisten und freigeben (Beispiel, manuell auf dem Server ausführen):"
  echo "    usbip list -l"
  echo "    sudo usbip bind -b <busid>"
  echo "Auf dem Client (im selben Tailnet):"
  echo "    usbip list -r <Tailscale-IP von node6>"
  echo "    sudo usbip attach -r <Tailscale-IP von node6> -b <busid>"
}

# --- WebAuthn/FIDO2: nur Pakete + Anleitung, keine PAM-Aktivierung ---
setup_webauthn() {
  need_pkg fido2-token libfido2-1
  need_pkg pamu2fcfg libpam-u2f
  apt_package_available fido2-tools && need_pkg fido2-cred fido2-tools

  echo ">>> WebAuthn/FIDO2-Pakete installiert. PAM wird bewusst NICHT verändert"
  echo "(Risiko Login-Lockout auf einem Headless-Server). Aktivierung bei Bedarf manuell:"
  echo "    fido2-token -L                       # Sicherheitsschlüssel erkennen"
  echo "    pamu2fcfg > ~/.config/Yubico/u2f_keys # eigenen Schlüssel registrieren"
  echo "    # danach in /etc/pam.d/ manuell 'pam_u2f.so' ergänzen, siehe libpam-u2f-Doku"
}

setup_firewall_base
has_component gnome-rdp && setup_tailscale
has_component gnome-rdp && setup_gnome_rdp
has_component audio && setup_audio
has_component usbip && setup_usbip
has_component webauthn && setup_webauthn

echo
echo ">>> FERTIG."
echo "Kontrolle:"
echo "  systemctl get-default                      # sollte multi-user.target bleiben"
echo "  systemctl status gnome-remote-desktop tailscaled usbipd"
echo "  ufw status verbose                         # RDP/usbip nur auf ${TAILSCALE_IFACE}"
echo "  tailscale ip -4                             # Adresse für RDP-/usbip-Clients"
echo
echo "Verbindungsaufbau vom Client (im selben Tailnet):"
echo "  RDP-Client auf <Tailscale-IP>:3389 verbinden - GNOME-Session startet automatisch,"
echo "  Audio kommt über den RDP-Kanal mit."
