#!/usr/bin/env bash
set -euo pipefail

echo ">>> GNOME-Remote-Setup: GNOME RDP über Tailscale + Audio + USB-over-IP + WebAuthn-Vorbereitung"

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen." >&2
  exit 1
fi

ASSUME_YES=${LAYOUT_SCRIPT_ASSUME_YES:-0}
REMOTE_MODE=${GNOME_REMOTE_MODE:-}
RDP_USER=${GNOME_REMOTE_USER:-}
RDP_CERT=""
RDP_KEY=""
RDP_HOME=""
USER_RUNTIME_DIR=""

apt_package_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

need_pkg() {
  local cmd="$1" pkg="$2"
  if command -v "$cmd" >/dev/null 2>&1 || package_installed "$pkg"; then
    echo ">>> Abhängigkeit $pkg ist bereits vorhanden."
    return 0
  fi

  echo ">>> Installiere benötigtes Paket: $pkg"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
}

need_package() {
  local pkg="$1"
  if package_installed "$pkg"; then
    echo ">>> Abhängigkeit $pkg ist bereits vorhanden."
    return 0
  fi

  echo ">>> Installiere benötigtes Paket: $pkg"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
}

confirm_or_abort() {
  if [[ -t 0 ]]; then
    read -r -p "Fortfahren? Exakt 'ja' eingeben: " CONFIRM
    if [[ "$CONFIRM" != "ja" ]]; then
      echo "Abgebrochen." >&2
      exit 1
    fi
  elif [[ "$ASSUME_YES" == "1" ]]; then
    echo ">>> Nicht-interaktiver Lauf mit LAYOUT_SCRIPT_ASSUME_YES=1 bestätigt."
  else
    echo "FEHLER: Kein interaktives Terminal. Setze LAYOUT_SCRIPT_ASSUME_YES=1 für automatisierte Läufe." >&2
    exit 1
  fi
}

choose_mode() {
  case "$REMOTE_MODE" in
    single-user-headless|gdm-remote-login) return 0 ;;
    "") ;;
    *)
      echo "FEHLER: GNOME_REMOTE_MODE muss single-user-headless oder gdm-remote-login sein." >&2
      exit 1
      ;;
  esac

  if [[ -t 0 && -t 1 ]]; then
    need_pkg whiptail whiptail
    REMOTE_MODE=$(whiptail --title "GNOME-RDP-Modus auswählen" \
      --radiolist "Single-User braucht keinen Display-Manager. GDM Remote Login ist näher am GNOME-Login, nutzt aber GDM/graphical.target." \
      16 82 2 \
      "single-user-headless" "Ein fester Linux-User, kein GDM/graphical.target" ON \
      "gdm-remote-login" "Systemweiter GNOME-Remote-Login über GDM" OFF \
      3>&1 1>&2 2>&3) || { echo "Abgebrochen." >&2; exit 1; }
  else
    echo "FEHLER: Nicht-interaktiv muss GNOME_REMOTE_MODE gesetzt sein." >&2
    exit 1
  fi
}

choose_user() {
  if [[ -n "$RDP_USER" ]]; then
    id "$RDP_USER" >/dev/null
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -p "Linux-Zielbenutzer für die headless GNOME-RDP-Session: " RDP_USER
    id "$RDP_USER" >/dev/null
  else
    echo "FEHLER: Für single-user-headless muss GNOME_REMOTE_USER gesetzt sein." >&2
    exit 1
  fi
}

echo
echo "!!! ACHTUNG !!!"
echo "Dieses Skript installiert GNOME-RDP-Komponenten, Tailscale und optionale"
echo "Audio-, USB-over-IP- und WebAuthn-Pakete. RDP und usbip werden per ufw"
echo "auf tailscale0 beschränkt; SSH wird vor dem Aktivieren der Firewall erlaubt."
echo "GNOME Remote Desktop ist keine Garantie für weiterlaufende GUI-Sessions"
echo "nach einem Verbindungsabbruch. Lange Jobs sollten per systemd, tmux oder"
echo "einem anderen nicht-GUI Mechanismus gestartet werden."
echo
confirm_or_abort

declare -a COMPONENTS=(gnome-rdp audio usbip webauthn)
if [[ -t 0 && -t 1 ]]; then
  need_pkg whiptail whiptail
  SELECTED=$(whiptail --title "GNOME-Remote-Komponenten auswählen" \
    --checklist "Alle Komponenten sind vorausgewählt. Leertaste = ab-/anwählen, Enter = bestätigen." \
    18 78 4 \
    "gnome-rdp" "GNOME RDP über Tailscale" ON \
    "audio" "PipeWire/WirePlumber-Audio über RDP" ON \
    "usbip" "USB-over-IP-Server (usbip) über Tailscale" ON \
    "webauthn" "WebAuthn/FIDO2-Pakete vorbereiten (kein PAM-Zwang)" ON \
    3>&1 1>&2 2>&3) || { echo "Abgebrochen." >&2; exit 1; }
  eval "COMPONENTS=($SELECTED)"
else
  echo ">>> Kein interaktives Terminal – alle vier Komponenten werden eingerichtet."
fi

has_component() {
  local c
  for c in "${COMPONENTS[@]}"; do
    [[ "$c" == "$1" ]] && return 0
  done
  return 1
}

has_component gnome-rdp && choose_mode

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

setup_tailscale() {
  if ! command -v tailscale >/dev/null 2>&1; then
    need_pkg curl curl
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

install_gnome_base() {
  local pkg
  for pkg in gnome-session gnome-shell mutter gnome-remote-desktop; do
    need_package "$pkg"
  done
}

create_rdp_cert() {
  local cert_dir="$1" owner="${2:-}"
  RDP_CERT="$cert_dir/rdp-tls.crt"
  RDP_KEY="$cert_dir/rdp-tls.key"
  need_pkg openssl openssl
  if [[ -f "$RDP_CERT" && -f "$RDP_KEY" ]]; then
    echo ">>> TLS-Zertifikat für RDP existiert bereits, überspringe Erzeugung."
  else
    echo ">>> Erzeuge selbstsigniertes TLS-Zertifikat für RDP"
    mkdir -p "$cert_dir"
    openssl req -new -x509 -days 3650 -nodes -newkey rsa:4096 \
      -keyout "$RDP_KEY" -out "$RDP_CERT" \
      -subj "/CN=$(hostname -f 2>/dev/null || hostname)"
  fi
  chmod 644 "$RDP_CERT"
  chmod 600 "$RDP_KEY"
  if [[ -n "$owner" ]]; then
    chown "$owner:" "$RDP_CERT" "$RDP_KEY"
  fi
}

read_rdp_credentials() {
  RDP_LOGIN=""
  RDP_PASSWORD_VALUE=""

  if [[ -n "${GNOME_REMOTE_RDP_USERNAME:-}" && -n "${GNOME_REMOTE_RDP_PASSWORD:-}" ]]; then
    RDP_LOGIN=$GNOME_REMOTE_RDP_USERNAME
    RDP_PASSWORD_VALUE=$GNOME_REMOTE_RDP_PASSWORD
  elif [[ -t 0 ]]; then
    echo ">>> RDP-Zugangsdaten festlegen (werden nur an grdctl übergeben, nicht gespeichert)"
    read -r -p "RDP-Benutzername: " RDP_LOGIN
    read -r -s -p "RDP-Passwort: " RDP_PASSWORD_VALUE
    echo
  else
    echo ">>> Kein interaktives Terminal – RDP-Zugangsdaten bitte danach manuell setzen."
    return 1
  fi

  return 0
}

run_as_rdp_user() {
  runuser -u "$RDP_USER" -- env HOME="$RDP_HOME" USER="$RDP_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" "$@"
}

set_system_rdp_credentials() {
  if read_rdp_credentials; then
    grdctl --system rdp set-credentials "$RDP_LOGIN" "$RDP_PASSWORD_VALUE"
    unset RDP_PASSWORD_VALUE
  else
    echo "    sudo grdctl --system rdp set-credentials <Benutzer> <Passwort>"
  fi
}

set_headless_rdp_credentials() {
  if read_rdp_credentials; then
    run_as_rdp_user grdctl --headless rdp set-credentials "$RDP_LOGIN" "$RDP_PASSWORD_VALUE"
    unset RDP_PASSWORD_VALUE
  else
    echo "    sudo -u $RDP_USER XDG_RUNTIME_DIR=$USER_RUNTIME_DIR grdctl --headless rdp set-credentials <Benutzer> <Passwort>"
  fi
}

setup_single_user_headless() {
  local target_before target_after uid cert_dir

  choose_user
  RDP_HOME=$(getent passwd "$RDP_USER" | cut -d: -f6)
  if [[ -z "$RDP_HOME" || ! -d "$RDP_HOME" ]]; then
    echo "FEHLER: Home-Verzeichnis für $RDP_USER nicht gefunden." >&2
    exit 1
  fi

  echo ">>> Richte GNOME Remote Desktop als Single-User-Headless-Session für $RDP_USER ein"
  target_before=$(systemctl get-default)
  install_gnome_base
  target_after=$(systemctl get-default)
  if [[ "$target_after" != "$target_before" ]]; then
    echo "WARNUNG: Ein Paket hat das Default-Target auf '$target_after' geändert." >&2
    echo ">>> Setze Default-Target zurück auf '$target_before'."
    systemctl set-default "$target_before"
  fi

  cert_dir="$RDP_HOME/.local/share/gnome-remote-desktop"
  create_rdp_cert "$cert_dir" "$RDP_USER"
  loginctl enable-linger "$RDP_USER"
  uid=$(id -u "$RDP_USER")
  USER_RUNTIME_DIR="/run/user/$uid"
  systemctl start "user@${uid}.service"
  mkdir -p "$USER_RUNTIME_DIR"
  chown "$RDP_USER:$RDP_USER" "$USER_RUNTIME_DIR"
  chmod 700 "$USER_RUNTIME_DIR"

  run_as_rdp_user grdctl --headless rdp enable
  run_as_rdp_user grdctl --headless rdp disable-view-only
  run_as_rdp_user grdctl --headless rdp set-tls-cert "$RDP_CERT"
  run_as_rdp_user grdctl --headless rdp set-tls-key "$RDP_KEY"
  set_headless_rdp_credentials

  run_as_rdp_user systemctl --user daemon-reload
  run_as_rdp_user systemctl --user enable --now gnome-remote-desktop-headless.service
}

setup_gdm_remote_login() {
  echo ">>> Richte GNOME Remote Desktop als GDM Remote Login ein"
  need_package gdm3
  install_gnome_base
  systemctl set-default graphical.target
  systemctl enable --now gdm3
  create_rdp_cert "/etc/gnome-remote-desktop"
  if id gnome-remote-desktop >/dev/null 2>&1; then
    chown root:gnome-remote-desktop "$RDP_KEY"
    chmod 640 "$RDP_KEY"
  fi

  grdctl --system rdp enable
  grdctl --system rdp disable-view-only
  grdctl --system rdp set-tls-cert "$RDP_CERT"
  grdctl --system rdp set-tls-key "$RDP_KEY"
  set_system_rdp_credentials
  systemctl enable --now gnome-remote-desktop.service
}

setup_gnome_rdp() {
  if [[ "$REMOTE_MODE" == "single-user-headless" ]]; then
    setup_single_user_headless
  else
    setup_gdm_remote_login
  fi

  echo ">>> Beschränke RDP (3389) per ufw auf das Tailscale-Interface ${TAILSCALE_IFACE}"
  ufw allow in on "$TAILSCALE_IFACE" to any port 3389 proto tcp
}

setup_audio() {
  need_pkg pipewire pipewire
  need_pkg wireplumber wireplumber
  apt_package_available pipewire-pulse && need_pkg pipewire-pulse pipewire-pulse

  echo ">>> Aktiviere PipeWire/WirePlumber global für zukünftige Nutzersessions"
  for unit in pipewire.service pipewire-pulse.service wireplumber.service; do
    if systemctl --global list-unit-files "$unit" >/dev/null 2>&1 &&
      systemctl --global list-unit-files "$unit" | grep -q "$unit"; then
      systemctl --global enable "$unit"
    else
      echo "WARNUNG: User-Unit $unit nicht gefunden, überspringe." >&2
    fi
  done
}

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

setup_webauthn() {
  need_pkg fido2-token libfido2-1
  need_pkg pamu2fcfg libpam-u2f
  apt_package_available fido2-tools && need_pkg fido2-cred fido2-tools

  echo ">>> WebAuthn/FIDO2-Pakete installiert. PAM wird bewusst NICHT verändert"
  echo "(Risiko Login-Lockout auf einem Headless-Server). Aktivierung bei Bedarf manuell:"
  echo "    fido2-token -L"
  echo "    pamu2fcfg > ~/.config/Yubico/u2f_keys"
  echo "    # danach in /etc/pam.d/ manuell 'pam_u2f.so' ergänzen"
}

if has_component gnome-rdp || has_component usbip; then
  setup_firewall_base
  setup_tailscale
fi
has_component gnome-rdp && setup_gnome_rdp
has_component audio && setup_audio
has_component usbip && setup_usbip
has_component webauthn && setup_webauthn

echo
echo ">>> FERTIG."
echo "Kontrolle:"
if has_component gnome-rdp || has_component usbip; then
  echo "  ufw status verbose"
  echo "  tailscale ip -4"
fi
if has_component gnome-rdp; then
  if [[ "$REMOTE_MODE" == "single-user-headless" ]]; then
    echo "  sudo -u $RDP_USER XDG_RUNTIME_DIR=/run/user/$(id -u "$RDP_USER") systemctl --user status gnome-remote-desktop-headless.service"
    echo "  sudo -u $RDP_USER XDG_RUNTIME_DIR=/run/user/$(id -u "$RDP_USER") grdctl --headless status"
  else
    echo "  systemctl status gdm3 gnome-remote-desktop"
    echo "  grdctl --system status"
  fi
fi
echo
echo "Hinweis:"
echo "GNOME Remote Desktop kann Remote-Sessions bei Netzwerk-Disconnect beenden."
echo "Für lange Jobs bitte systemd, tmux oder einen anderen persistenten"
echo "nicht-GUI Mechanismus verwenden."
