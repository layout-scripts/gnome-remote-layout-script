# gnome-remote-layout-script

`setup-gnome-remote.sh` convierte un servidor Debian, Ubuntu u otro basado en Debian en una máquina accesible mediante GNOME Remote Desktop/RDP a través de [Tailscale](https://tailscale.com/) — con audio, USB-over-IP y paquetes WebAuthn/FIDO2 preparados. Durante la instalación se elige entre un modo headless de un solo usuario sin gestor de pantallas y un modo de inicio de sesión remoto con GDM.

## Idiomas

- [English](README.md)
- [Deutsch](README.de.md)
- Español (este archivo)

## Qué hace el script

En un sistema Debian (o basado en Debian) con `systemd`, el script ofrece cuatro componentes seleccionables de forma independiente (todos preseleccionados en un diálogo interactivo `whiptail`, todos se instalan en una ejecución automatizada). Si se selecciona GNOME + RDP, también pregunta por el modo GNOME-RDP:

- **GNOME + RDP**
  - **Single-user headless**: instala `gnome-session`, `gnome-shell`, `mutter` y `gnome-remote-desktop`, activa `loginctl enable-linger` para un usuario Linux elegido y arranca su `gnome-remote-desktop-headless.service`. El servidor conserva su target predeterminado anterior, normalmente `multi-user.target`; no requiere GDM.
  - **GDM remote login**: instala además `gdm3`, cambia a `graphical.target` y activa la ruta de inicio de sesión remoto GNOME a nivel de sistema. Es más parecido a una pantalla de login GNOME, pero incluye deliberadamente un gestor de pantallas.
  - Genera un certificado TLS autofirmado para RDP si aún no existe, lo configura con `grdctl` y pide de forma interactiva las credenciales RDP — las credenciales solo se pasan a `grdctl`, nunca las guarda el propio script.
  - Restringe RDP (puerto 3389) mediante `ufw` únicamente a la interfaz `tailscale0`.
- **Audio (PipeWire)**: instala `pipewire`, `pipewire-pulse`, `wireplumber` y los activa `--global` para que el audio funcione también en la sesión bajo demanda iniciada por el RDP headless, sin que nadie haya iniciado sesión interactivamente antes.
- **USB-over-IP (usbip)**: instala `usbip` y el paquete `linux-tools-<kernel>` correspondiente al kernel, carga de forma persistente los módulos del kernel `usbip-core`/`usbip_host`/`vhci-hcd`, escribe una pequeña unidad `usbipd.service` (Ubuntu no incluye una lista para usar) y restringe el puerto 3240 a `tailscale0` mediante `ufw`.
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

3. Si se solicita, autenticar Tailscale (`sudo tailscale up`) y volver a ejecutar el script.

4. Verificar:

   ```bash
   systemctl get-default                 # single-user: debe seguir en multi-user.target; GDM: graphical.target
   systemctl status tailscaled usbipd
   ufw status verbose                    # RDP/usbip solo en tailscale0
   tailscale ip -4
   ```

5. Desde otro dispositivo en la misma tailnet, conectar un cliente RDP a `<ip-tailscale>:3389` — según el modo elegido, la conexión entra en la sesión headless de un solo usuario o en el inicio remoto de GDM.

## Licencia

Este proyecto está licenciado bajo la **GNU General Public License v3.0 o posterior (GPL-3.0-or-later)**.

Ver el archivo `LICENSE` para más detalles.
