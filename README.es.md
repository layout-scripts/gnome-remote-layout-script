# gnome-remote-layout-script

`setup-gnome-remote.sh` convierte un servidor Debian, Ubuntu u otro basado en Debian en una estación de trabajo remota GNOME usable mediante GNOME Remote Desktop/RDP. Además de [Tailscale](https://tailscale.com/), puede preparar túneles SSH y WireGuard; audio, micrófono, acceso a archivos, USB-over-IP, opciones de webcam y paquetes WebAuthn/FIDO2 son seleccionables.

## Idiomas

- [English](README.md)
- [Deutsch](README.de.md)
- Español (este archivo)

## Qué hace el script

En un sistema Debian (o basado en Debian) con `systemd`, el script ofrece componentes, perfiles de escritorio, opciones de webcam y transportes privados seleccionables. Si se selecciona GNOME + RDP, también pregunta por el modo GNOME-RDP:

- **GNOME + RDP**
  - **Single-user headless**: instala `gnome-session`, `gnome-shell`, `mutter` y `gnome-remote-desktop`, activa `loginctl enable-linger` para un usuario Linux elegido y arranca su `gnome-remote-desktop-headless.service`. El servidor conserva su target predeterminado anterior, normalmente `multi-user.target`; no requiere GDM.
  - **GDM remote login**: instala además `gdm3`, cambia a `graphical.target` y activa la ruta de inicio de sesión remoto GNOME a nivel de sistema. Es más parecido a una pantalla de login GNOME, pero incluye deliberadamente un gestor de pantallas.
  - Genera un certificado TLS autofirmado para RDP si aún no existe, lo configura con `grdctl` y pide de forma interactiva las credenciales RDP — las credenciales solo se pasan a `grdctl`, nunca las guarda el propio script.
  - Restringe RDP (puerto 3389) mediante `ufw` a las interfaces privadas elegidas; en modo túnel SSH, RDP no se abre directamente.
- **Base de escritorio**: el perfil predeterminado `workstation` instala una base GNOME curada con terminal, Archivos, Configuración, portales, GVFS/FUSE/backends, llavero, fuentes, herramientas del sistema y acceso a archivos. `minimal` omite estos extras; `ubuntu-desktop-minimal` está pensado solo para Ubuntu.
- **Intercambio de archivos**: instala portales y GVFS backends para portapapeles/portal y acceso a archivos en la sesión remota. No activa automáticamente un servidor público de archivos.
- **Audio (PipeWire)**: instala PipeWire con Pulse/ALSA, WirePlumber, GStreamer/PipeWire y portales básicos para preparar altavoces y micrófono en GNOME RDP.
- **USB-over-IP (usbip)**: instala `linux-tools-<kernel>` correspondiente al kernel en ejecución, con fallbacks HWE de Ubuntu, carga `usbip-core`/`usbip_host`/`vhci-hcd`, escribe `usbipd.service` y restringe el puerto 3240 a transportes privados.
- **Webcam**: `usbip-webcam` prepara webcams USB físicas mediante USB-over-IP junto con herramientas de prueba de cámara. Opcionalmente `virtual-webcam` instala también `v4l2loopback`, `ffmpeg`, `pipewire-v4l2` y herramientas V4L2. No se asume que GNOME RDP proporcione redirección nativa fiable de webcam.
- **Transportes**:
  - **Tailscale**: instala/activa Tailscale y permite RDP/usbip en `tailscale0`.
  - **Túnel SSH**: instala/activa OpenSSH, permite solo SSH y muestra comandos de port-forwarding local para RDP y opcionalmente usbip.
  - **WireGuard**: instala herramientas WireGuard. Solo activa un túnel si se define `GNOME_REMOTE_WIREGUARD_CONFIG=/ruta/wg0.conf`; si no, solo instala los requisitos.
- **WebAuthn/FIDO2 (solo preparación)**: instala `libfido2-1`, `libpam-u2f`, `fido2-tools`. PAM en sí **no** se modifica automáticamente — habilitar una llave de seguridad para el inicio de sesión es un paso manual deliberado (`pamu2fcfg`, luego editar `/etc/pam.d/` a mano), para nunca arriesgarse a quedar bloqueado en un servidor sin interfaz gráfica.

Antes de tocar el cortafuegos, el script siempre permite primero SSH (`ufw allow OpenSSH`), de modo que una sesión remota nunca pueda bloquearse a sí misma.

Tailscale se instala mediante el script oficial `https://tailscale.com/install.sh` si falta; si aún no está autenticado, el script muestra un recordatorio para ejecutar `sudo tailscale up` y continúa después.

GNOME Remote Desktop no garantiza que una sesión gráfica siga ejecutándose después de una desconexión de red y pueda retomarse más tarde. Para trabajos largos conviene usar `systemd`, `tmux` u otro mecanismo que no dependa de la GUI.

## Requisitos

- Sistema Debian o basado en Debian con `apt` y `systemd`.
- Ejecutar el script como **root**.
- Acceso saliente a internet (script de instalación de Tailscale, paquetes apt).

## Uso

1. Clonar este repositorio:

   ```bash
   git clone https://github.com/layout-scripts/gnome-remote-layout-script.git
   cd gnome-remote-layout-script
   ```

2. Hacer el script ejecutable y ejecutarlo:

   ```bash
   chmod +x setup-gnome-remote.sh
   sudo ./setup-gnome-remote.sh
   ```

   Para ejecuciones automatizadas sin terminal:

   ```bash
   sudo LAYOUT_SCRIPT_ASSUME_YES=1 GNOME_REMOTE_MODE=single-user-headless GNOME_REMOTE_USER=<usuario-linux> ./setup-gnome-remote.sh
   # o:
   sudo LAYOUT_SCRIPT_ASSUME_YES=1 GNOME_REMOTE_MODE=gdm-remote-login ./setup-gnome-remote.sh
   ```

   Opciones importantes de entorno:

   ```bash
   GNOME_REMOTE_COMPONENTS=desktop-baseline,gnome-rdp,audio,usbip,webauthn
   GNOME_REMOTE_DESKTOP_PROFILE=workstation        # workstation|minimal|ubuntu-desktop-minimal
   GNOME_REMOTE_TRANSPORTS=tailscale,ssh-tunnel,wireguard
   GNOME_REMOTE_WEBCAM=usbip,virtual               # usbip|virtual|none, combinables
   GNOME_REMOTE_WIREGUARD_CONFIG=/root/wg0.conf    # opcional
   ```

3. Si se solicita, autenticar Tailscale (`sudo tailscale up`) y volver a ejecutar el script.

4. Verificar:

   ```bash
   systemctl get-default                 # single-user: debe seguir en multi-user.target; GDM: graphical.target
   systemctl status tailscaled usbipd
   ufw status verbose                    # RDP/usbip solo por transportes privados elegidos
   tailscale ip -4                       # si se eligió Tailscale
   wg show                               # si WireGuard está activo
   ```

5. Desde otro dispositivo, conectar un cliente RDP a `<ip-privada>:3389` por Tailscale/WireGuard. Para túneles SSH:

   ```bash
   ssh -L 3389:127.0.0.1:3389 <usuario>@<servidor>
   # también con usbip:
   ssh -L 3389:127.0.0.1:3389 -L 3240:127.0.0.1:3240 <usuario>@<servidor>
   ```

   Después el cliente RDP se conecta a `localhost:3389`.

## Licencia

Este proyecto está licenciado bajo la **GNU General Public License v3.0 o posterior (GPL-3.0-or-later)**.

Ver el archivo `LICENSE` para más detalles.
