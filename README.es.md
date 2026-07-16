# gnome-remote-layout-script

`setup-gnome-remote.sh` convierte un servidor Debian, Ubuntu u otro basado en Debian sin interfaz gráfica en una máquina accesible como un escritorio remoto GNOME completo a través de [Tailscale](https://tailscale.com/) — con audio, USB-over-IP y paquetes WebAuthn/FIDO2 preparados. El comportamiento de arranque no cambia: **no hay gestor de pantallas ni inicio de sesión gráfico**. GNOME solo se inicia bajo demanda, en el momento en que se conecta un cliente RDP, y se cierra de nuevo después.

## Idiomas

- [English](README.md)
- [Deutsch](README.de.md)
- Español (este archivo)

## Qué hace el script

En un sistema Debian (o basado en Debian) con `systemd`, el script ofrece cuatro componentes seleccionables de forma independiente (todos preseleccionados en un diálogo interactivo `whiptail`, todos se instalan en una ejecución automatizada):

- **GNOME + RDP, verdaderamente sin interfaz gráfica, bajo demanda**
  - Instala solo `gnome-session`, `gnome-shell`, `mutter` y `gnome-remote-desktop` — deliberadamente **no** los metapaquetes `ubuntu-desktop`/`ubuntu-desktop-minimal`, ya que estos incluyen `gdm3` y suelen cambiar el sistema a `graphical.target` al instalarse.
  - Registra `systemctl get-default` antes de instalar y lo restablece si alguna dependencia lo cambió, de modo que la máquina siga arrancando en `multi-user.target`.
  - Activa el **modo headless a nivel de sistema** de `gnome-remote-desktop` (`gnome-remote-desktop.service`): una sesión de GNOME se inicia automáticamente solo cuando se conecta un cliente RDP, y se cierra después — sin consumo de recursos en reposo.
  - Genera un certificado TLS autofirmado para RDP si aún no existe, lo configura mediante `grdctl --system rdp set-tls-cert/-key` y pide de forma interactiva las credenciales RDP (`grdctl --system rdp set-credentials`) — las credenciales solo se pasan a `grdctl`, nunca las guarda el propio script.
  - Restringe RDP (puerto 3389) mediante `ufw` únicamente a la interfaz `tailscale0`.
- **Audio (PipeWire)**: instala `pipewire`, `pipewire-pulse`, `wireplumber` y los activa `--global` para que el audio funcione también en la sesión bajo demanda iniciada por el RDP headless, sin que nadie haya iniciado sesión interactivamente antes.
- **USB-over-IP (usbip)**: instala `usbip` y el paquete `linux-tools-<kernel>` correspondiente al kernel, carga de forma persistente los módulos del kernel `usbip-core`/`usbip_host`/`vhci-hcd`, escribe una pequeña unidad `usbipd.service` (Ubuntu no incluye una lista para usar) y restringe el puerto 3240 a `tailscale0` mediante `ufw`.
- **WebAuthn/FIDO2 (solo preparación)**: instala `libfido2-1`, `libpam-u2f`, `fido2-tools`. PAM en sí **no** se modifica automáticamente — habilitar una llave de seguridad para el inicio de sesión es un paso manual deliberado (`pamu2fcfg`, luego editar `/etc/pam.d/` a mano), para nunca arriesgarse a quedar bloqueado en un servidor sin interfaz gráfica.

Antes de tocar el cortafuegos, el script siempre permite primero SSH (`ufw allow OpenSSH`), de modo que una sesión remota nunca pueda bloquearse a sí misma.

Tailscale se instala mediante el script oficial `https://tailscale.com/install.sh` si falta; si aún no está autenticado, el script muestra un recordatorio para ejecutar `sudo tailscale up` y continúa después.

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

3. Si se solicita, autenticar Tailscale (`sudo tailscale up`) y volver a ejecutar el script.

4. Verificar:

   ```bash
   systemctl get-default                 # debe seguir siendo multi-user.target
   systemctl status gnome-remote-desktop tailscaled usbipd
   ufw status verbose                    # RDP/usbip solo en tailscale0
   tailscale ip -4
   ```

5. Desde otro dispositivo en la misma tailnet, conectar un cliente RDP a `<ip-tailscale>:3389` — una sesión de GNOME debería iniciarse automáticamente, con audio a través del canal RDP.

## Licencia

Este proyecto está licenciado bajo la **GNU General Public License v3.0 o posterior (GPL-3.0-or-later)**.

Ver el archivo `LICENSE` para más detalles.
