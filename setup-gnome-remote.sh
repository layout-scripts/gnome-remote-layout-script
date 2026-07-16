#!/usr/bin/env bash
set -euo pipefail

echo ">>> GNOME-Remote-Setup: GNOME RDP + Workstation-Basis + Audio/Video + USB/Webcam + private Transporte"

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen." >&2
  exit 1
fi

ASSUME_YES=${LAYOUT_SCRIPT_ASSUME_YES:-0}
REMOTE_MODE=${GNOME_REMOTE_MODE:-}
DESKTOP_PROFILE=${GNOME_REMOTE_DESKTOP_PROFILE:-}
TRANSPORTS_VALUE=${GNOME_REMOTE_TRANSPORTS:-}
WEBCAM_VALUE=${GNOME_REMOTE_WEBCAM:-}
RDP_USER=${GNOME_REMOTE_USER:-}
WIREGUARD_CONFIG=${GNOME_REMOTE_WIREGUARD_CONFIG:-}
WIREGUARD_IFACE=${GNOME_REMOTE_WIREGUARD_IFACE:-wg0}
RDP_CERT=""
RDP_KEY=""
RDP_HOME=""
USER_RUNTIME_DIR=""
OS_ID=""
OS_VERSION_ID=""
TAILSCALE_IFACE="tailscale0"
declare -a COMPONENTS=(desktop-baseline gnome-rdp audio usbip webauthn)
declare -a TRANSPORTS=()
declare -a WEBCAM_OPTIONS=()

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID=${ID:-}
  OS_VERSION_ID=${VERSION_ID:-}
fi

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

install_available_packages() {
  local pkg
  for pkg in "$@"; do
    if apt_package_available "$pkg"; then
      need_package "$pkg"
    else
      echo "WARNUNG: Paket $pkg ist in diesem APT-Repository nicht verfügbar, überspringe." >&2
    fi
  done
}

install_first_available() {
  local pkg
  for pkg in "$@"; do
    if apt_package_available "$pkg"; then
      need_package "$pkg"
      return 0
    fi
  done
  echo "WARNUNG: Keines dieser Pakete ist verfügbar: $*" >&2
  return 1
}

parse_csv_words() {
  local value="$1" out_name="$2" item
  local -n out_ref="$out_name"
  out_ref=()
  value=${value//,/ }
  for item in $value; do
    [[ -n "$item" ]] && out_ref+=("$item")
  done
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

choose_desktop_profile() {
  case "$DESKTOP_PROFILE" in
    workstation|minimal|ubuntu-desktop-minimal) return 0 ;;
    "") ;;
    *)
      echo "FEHLER: GNOME_REMOTE_DESKTOP_PROFILE muss workstation, minimal oder ubuntu-desktop-minimal sein." >&2
      exit 1
      ;;
  esac

  if [[ -t 0 && -t 1 ]]; then
    need_pkg whiptail whiptail
    DESKTOP_PROFILE=$(whiptail --title "Desktop-Profil auswählen" \
      --radiolist "workstation installiert eine nutzbare GNOME-Basis ohne komplettes Ubuntu-Metapaket." \
      17 84 3 \
      "workstation" "GNOME-Basis mit Dateien, Terminal, Settings, Portals, GVFS, Fonts" ON \
      "minimal" "Nur GNOME Remote Desktop und harte Remote-Abhängigkeiten" OFF \
      "ubuntu-desktop-minimal" "Ubuntu-Metapaket, schwerer und Ubuntu-spezifisch" OFF \
      3>&1 1>&2 2>&3) || { echo "Abgebrochen." >&2; exit 1; }
  else
    DESKTOP_PROFILE=workstation
    echo ">>> Kein Desktop-Profil gesetzt – verwende GNOME_REMOTE_DESKTOP_PROFILE=workstation."
  fi
}

choose_transports() {
  if [[ -n "$TRANSPORTS_VALUE" ]]; then
    parse_csv_words "$TRANSPORTS_VALUE" TRANSPORTS
  elif [[ -t 0 && -t 1 ]]; then
    need_pkg whiptail whiptail
    SELECTED_TRANSPORTS=$(whiptail --title "Remote-Transporte auswählen" \
      --checklist "Mehrfachauswahl ist möglich. SSH-Tunnel öffnet keinen RDP-Port nach außen." \
      18 86 3 \
      "tailscale" "Tailscale-Interface ${TAILSCALE_IFACE}" ON \
      "ssh-tunnel" "OpenSSH für lokale RDP-Tunnel" ON \
      "wireguard" "WireGuard-Tools, optional wg-quick per Config" ON \
      3>&1 1>&2 2>&3) || { echo "Abgebrochen." >&2; exit 1; }
    eval "TRANSPORTS=($SELECTED_TRANSPORTS)"
  else
    TRANSPORTS=(tailscale ssh-tunnel wireguard)
    echo ">>> Kein Transport gesetzt – verwende GNOME_REMOTE_TRANSPORTS=tailscale,ssh-tunnel,wireguard."
  fi

  local transport
  for transport in "${TRANSPORTS[@]}"; do
    case "$transport" in
      tailscale|ssh-tunnel|wireguard) ;;
      *)
        echo "FEHLER: Unbekannter Transport '$transport'. Erlaubt: tailscale, ssh-tunnel, wireguard." >&2
        exit 1
        ;;
    esac
  done
}

choose_webcam_options() {
  if [[ -n "$WEBCAM_VALUE" ]]; then
    if [[ "$WEBCAM_VALUE" == "none" ]]; then
      WEBCAM_OPTIONS=()
    else
      parse_csv_words "$WEBCAM_VALUE" WEBCAM_OPTIONS
    fi
  elif [[ -t 0 && -t 1 ]]; then
    need_pkg whiptail whiptail
    SELECTED_WEBCAMS=$(whiptail --title "Webcam-Optionen auswählen" \
      --checklist "GNOME RDP wird hier nicht als verlässliche native Webcam-Weiterleitung angenommen." \
      16 86 2 \
      "usbip-webcam" "USB-Webcams über USB-over-IP nutzen" ON \
      "virtual-webcam" "v4l2loopback/ffmpeg/PipeWire-V4L2 vorbereiten" OFF \
      3>&1 1>&2 2>&3) || { echo "Abgebrochen." >&2; exit 1; }
    eval "WEBCAM_OPTIONS=($SELECTED_WEBCAMS)"
  else
    WEBCAM_OPTIONS=(usbip-webcam)
    echo ">>> Keine Webcam-Option gesetzt – verwende GNOME_REMOTE_WEBCAM=usbip."
  fi

  local webcam
  for webcam in "${WEBCAM_OPTIONS[@]}"; do
    case "$webcam" in
      usbip|usbip-webcam) ;;
      virtual|virtual-webcam) ;;
      *)
        echo "FEHLER: Unbekannte Webcam-Option '$webcam'. Erlaubt: usbip, virtual, none." >&2
        exit 1
        ;;
    esac
  done
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
echo "Dieses Skript installiert GNOME-RDP-Komponenten, eine optionale"
echo "Workstation-Basis, private Transporte, Audio/Video, USB-over-IP/Webcam"
echo "und WebAuthn-Pakete. RDP und usbip werden per ufw nur auf ausgewählte"
echo "private Interfaces beschränkt; SSH wird vor dem Aktivieren der Firewall erlaubt."
echo "GNOME Remote Desktop ist keine Garantie für weiterlaufende GUI-Sessions"
echo "nach einem Verbindungsabbruch. Lange Jobs sollten per systemd, tmux oder"
echo "einem anderen nicht-GUI Mechanismus gestartet werden."
echo
confirm_or_abort

if [[ -t 0 && -t 1 ]]; then
  need_pkg whiptail whiptail
  SELECTED=$(whiptail --title "GNOME-Remote-Komponenten auswählen" \
    --checklist "Alle Komponenten sind vorausgewählt. Leertaste = ab-/anwählen, Enter = bestätigen." \
    20 86 5 \
    "desktop-baseline" "Nutzbare GNOME-Workstation-Basis" ON \
    "gnome-rdp" "GNOME RDP" ON \
    "audio" "PipeWire/WirePlumber-Audio, Mikrofon, Portals" ON \
    "usbip" "USB-over-IP-Server (usbip) für Geräte/Webcams" ON \
    "webauthn" "WebAuthn/FIDO2-Pakete vorbereiten (kein PAM-Zwang)" ON \
    3>&1 1>&2 2>&3) || { echo "Abgebrochen." >&2; exit 1; }
  eval "COMPONENTS=($SELECTED)"
else
  if [[ -n "${GNOME_REMOTE_COMPONENTS:-}" ]]; then
    parse_csv_words "$GNOME_REMOTE_COMPONENTS" COMPONENTS
  else
    echo ">>> Kein interaktives Terminal – Standardkomponenten werden eingerichtet."
  fi
fi

has_component() {
  local c
  for c in "${COMPONENTS[@]}"; do
    [[ "$c" == "$1" ]] && return 0
  done
  return 1
}

validate_components() {
  local component
  for component in "${COMPONENTS[@]}"; do
    case "$component" in
      desktop-baseline|gnome-rdp|audio|usbip|webauthn) ;;
      *)
        echo "FEHLER: Unbekannte Komponente '$component'. Erlaubt: desktop-baseline, gnome-rdp, audio, usbip, webauthn." >&2
        exit 1
        ;;
    esac
  done
}

has_transport() {
  local t
  for t in "${TRANSPORTS[@]}"; do
    [[ "$t" == "$1" ]] && return 0
  done
  return 1
}

has_webcam_option() {
  local w
  for w in "${WEBCAM_OPTIONS[@]}"; do
    [[ "$w" == "$1" || "$w" == "$2" ]] && return 0
  done
  return 1
}

validate_components

if has_component desktop-baseline || has_component gnome-rdp; then
  choose_desktop_profile
fi
if has_component gnome-rdp || has_component usbip; then
  choose_transports
  if [[ ${#TRANSPORTS[@]} -eq 0 ]]; then
    echo "FEHLER: GNOME RDP oder usbip brauchen mindestens einen Transport: tailscale, ssh-tunnel oder wireguard." >&2
    exit 1
  fi
fi
if has_component usbip; then
  choose_webcam_options
fi
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

allow_private_service_port() {
  local port="$1" label="$2"
  if has_transport tailscale; then
    echo ">>> Beschränke $label ($port/tcp) per ufw auf ${TAILSCALE_IFACE}"
    ufw allow in on "$TAILSCALE_IFACE" to any port "$port" proto tcp
  fi
  if has_transport wireguard && [[ -n "$WIREGUARD_IFACE" ]]; then
    echo ">>> Beschränke $label ($port/tcp) per ufw auf ${WIREGUARD_IFACE}"
    ufw allow in on "$WIREGUARD_IFACE" to any port "$port" proto tcp
  fi
  if has_transport ssh-tunnel; then
    echo ">>> SSH-Tunnel gewählt: $label wird nicht öffentlich geöffnet."
  fi
}

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

setup_ssh_tunnel_transport() {
  echo ">>> Richte OpenSSH für RDP/usbip-Tunnel ein"
  need_pkg sshd openssh-server
  systemctl enable --now ssh
  setup_firewall_base
  echo ">>> SSH-Tunnel vom Client:"
  if has_component usbip; then
    echo "    ssh -L 3389:127.0.0.1:3389 -L 3240:127.0.0.1:3240 <user>@<server>"
  else
    echo "    ssh -L 3389:127.0.0.1:3389 <user>@<server>"
  fi
  echo "    # RDP-Client danach mit localhost:3389 verbinden"
}

setup_wireguard_transport() {
  echo ">>> Richte WireGuard-Voraussetzungen ein"
  install_first_available wireguard-tools wireguard
  setup_firewall_base

  if [[ -n "$WIREGUARD_CONFIG" ]]; then
    if [[ ! -r "$WIREGUARD_CONFIG" ]]; then
      echo "FEHLER: GNOME_REMOTE_WIREGUARD_CONFIG ist nicht lesbar: $WIREGUARD_CONFIG" >&2
      exit 1
    fi
    local wg_name
    wg_name=$(basename "$WIREGUARD_CONFIG")
    wg_name=${wg_name%.conf}
    if [[ -z "$wg_name" ]]; then
      echo "FEHLER: WireGuard-Config braucht einen Dateinamen wie wg0.conf." >&2
      exit 1
    fi
    mkdir -p /etc/wireguard
    install -m 600 "$WIREGUARD_CONFIG" "/etc/wireguard/${wg_name}.conf"
    WIREGUARD_IFACE=$wg_name
    systemctl enable --now "wg-quick@${wg_name}.service"
    echo ">>> WireGuard-Profil ${wg_name} ist aktiviert."
  else
    echo ">>> Keine GNOME_REMOTE_WIREGUARD_CONFIG gesetzt; WireGuard-Tools sind installiert, aber kein Tunnel wurde aktiviert."
    echo "    Beispiel: sudo GNOME_REMOTE_TRANSPORTS=wireguard GNOME_REMOTE_WIREGUARD_CONFIG=/root/wg0.conf $0"
  fi
}

setup_transports() {
  if has_transport tailscale; then
    setup_firewall_base
    setup_tailscale
  fi
  has_transport ssh-tunnel && setup_ssh_tunnel_transport
  has_transport wireguard && setup_wireguard_transport
}

install_gnome_base() {
  local pkg
  for pkg in gnome-session gnome-shell mutter gnome-remote-desktop; do
    need_package "$pkg"
  done
}

install_desktop_baseline() {
  case "$DESKTOP_PROFILE" in
    minimal)
      echo ">>> Desktop-Profil minimal: keine zusätzliche Workstation-Basis."
      return 0
      ;;
    ubuntu-desktop-minimal)
      if [[ "$OS_ID" == "ubuntu" ]] && apt_package_available ubuntu-desktop-minimal; then
        need_package ubuntu-desktop-minimal
      else
        echo "WARNUNG: ubuntu-desktop-minimal ist hier nicht verfügbar; verwende workstation-Basis." >&2
        DESKTOP_PROFILE=workstation
      fi
      ;;
  esac

  [[ "$DESKTOP_PROFILE" != "workstation" ]] && return 0

  echo ">>> Installiere kuratierte GNOME-Workstation-Basis"
  install_available_packages \
    gnome-session gnome-shell mutter gnome-remote-desktop \
    gnome-settings-daemon gnome-control-center gnome-terminal nautilus \
    xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
    xdg-user-dirs xdg-user-dirs-gtk gvfs gvfs-fuse gvfs-backends fuse3 \
    openssh-client sshfs rsync \
    gnome-keyring libpam-gnome-keyring gnome-text-editor gedit \
    gnome-system-monitor gnome-disk-utility evince eog loupe file-roller \
    fonts-noto-core fonts-noto-color-emoji fonts-dejavu-core \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good
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

  allow_private_service_port 3389 RDP
}

setup_audio() {
  echo ">>> Installiere PipeWire-Audio, Mikrofon- und Portal-Grundlagen"
  install_available_packages \
    pipewire pipewire-audio pipewire-pulse pipewire-alsa wireplumber \
    gstreamer1.0-pipewire libspa-0.2-bluetooth libcanberra-pulse \
    xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk

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

install_usbip_tools() {
  if command -v usbip >/dev/null 2>&1 && command -v usbipd >/dev/null 2>&1; then
    echo ">>> usbip und usbipd sind bereits vorhanden."
    return 0
  fi

  if apt_package_available "linux-tools-$(uname -r)"; then
    need_package "linux-tools-$(uname -r)"
  elif [[ "$OS_ID" == "ubuntu" && "$OS_VERSION_ID" == "24.04" ]] && apt_package_available linux-tools-generic-hwe-24.04; then
    need_package linux-tools-generic-hwe-24.04
  elif apt_package_available linux-tools-generic; then
    need_package linux-tools-generic
  elif apt_package_available usbip; then
    need_package usbip
  else
    echo "FEHLER: Kein usbip/linux-tools-Paket in diesem Repository gefunden." >&2
    exit 1
  fi

  if ! command -v usbip >/dev/null 2>&1 || ! command -v usbipd >/dev/null 2>&1; then
    echo "FEHLER: usbip oder usbipd wurde nach der Installation nicht gefunden." >&2
    exit 1
  fi
}

setup_usbip() {
  install_usbip_tools

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

  allow_private_service_port 3240 usbip

  if has_webcam_option usbip usbip-webcam; then
    echo ">>> Installiere Kamera-/USB-Testwerkzeuge für USBIP-Webcams"
    install_available_packages v4l-utils guvcview cheese
  fi
  if has_webcam_option virtual virtual-webcam; then
    echo ">>> Installiere virtuelle Webcam-Werkzeuge"
    install_available_packages v4l2loopback-dkms v4l-utils ffmpeg pipewire-v4l2
  fi

  echo ">>> USB-Geräte auflisten und freigeben (Beispiel, manuell auf dem Server ausführen):"
  echo "    usbip list -l"
  echo "    sudo usbip bind -b <busid>"
  echo "Auf dem Client (über Tailscale, WireGuard oder SSH-Tunnel erreichbar):"
  echo "    usbip list -r <private-server-ip>"
  echo "    sudo usbip attach -r <private-server-ip> -b <busid>"
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

if has_component desktop-baseline; then
  install_desktop_baseline
fi
if has_component gnome-rdp || has_component usbip; then
  setup_transports
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
  has_transport tailscale && echo "  tailscale ip -4"
  has_transport wireguard && echo "  wg show"
  has_transport ssh-tunnel && echo "  ssh -L 3389:127.0.0.1:3389 <user>@<server>"
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
