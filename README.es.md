# vpsdoctor-mcp

[Read in English](README.md)

Un servidor [MCP](https://modelcontextprotocol.io) que permite a cualquier cliente de IA compatible (Claude Desktop, Claude Code, Cursor y otros) consultar el estado de un VPS Linux autoalojado y realizar tareas de mantenimiento seguras sobre él — por SSH normal y corriente, sin instalar ningún agente propietario en el servidor.

Pregunta "¿cómo va el servidor?" y obtienes el estado de los servicios, uso de disco y RAM, uptime, caducidad de los certificados TLS y un resumen de fail2ban. Si pides reiniciar un servicio o desbanear una IP, primero te explica exactamente qué va a pasar antes de tocar nada.

## Por qué

La mayoría de servidores MCP de monitorización de VPS o bien piden instalar un agente pesado, o le dan al modelo acceso de shell sin restricciones. Este no hace ninguna de las dos cosas:

- **Solo SSH.** Sin agente, sin ningún servicio adicional corriendo en el VPS aparte de lo que ya tienes.
- **Un conjunto cerrado de scripts revisados**, instalados una vez en `/opt/vpsdoctor-mcp` en el VPS, cada uno lo bastante corto como para leerlo en un minuto (ver [`scripts/`](scripts/)).
- **Un usuario del sistema dedicado y sin privilegios** en el VPS que, mediante una regla `sudoers` muy acotada, solo puede ejecutar esos scripts — nada más, sin shell root completa.
- **Las acciones destructivas piden confirmación explícita.** Reiniciar un servicio o desbanear una IP siempre requiere dos llamadas: la primera solo informa de qué pasaría y no hace nada; hace falta una segunda llamada con `confirm=true` para que se ejecute de verdad. Es el mismo enfoque "humano en el bucle" que usan el resto de agentes open source de VerticeDev.
- **Lista blanca de reinicio comprobada dos veces** — una vez en el servidor Python, otra vez en el propio script de shell en el VPS — para que un fallo en cualquiera de los dos lados no pueda reiniciar algo que no querías exponer.

## Qué expone

| Herramienta | ¿Solo lectura? | Qué hace |
|---|---|---|
| `vps_status` | sí | Servicios, disco, RAM, uptime, caducidad de certificados TLS, resumen de fail2ban, antigüedad del backup |
| `vps_list_banned_ips` | sí | IPs actualmente baneadas en una jaula de fail2ban |
| `vps_restart_service` | no | Reinicia un servicio de tu lista blanca (confirmación en dos pasos) |
| `vps_unban_ip` | no | Desbanea una IP de una jaula de fail2ban (confirmación en dos pasos) |

## Instalación

### 1. En el VPS

Copia la carpeta `scripts/` al VPS y ejecuta el instalador como root:

```bash
scp -r scripts/ tuusuario@tu-vps:/tmp/vpsdoctor-mcp-scripts
ssh tuusuario@tu-vps
cd /tmp/vpsdoctor-mcp-scripts && sudo ./install.sh
```

Esto crea un usuario del sistema dedicado `vpsdoctor-mcp`, instala los scripts en `/opt/vpsdoctor-mcp`, escribe una regla `sudoers` que limita ese usuario a exactamente esos scripts, y genera un par de claves SSH dedicado. Al terminar imprime los siguientes pasos, incluido dónde copiar la clave privada.

Edita `/opt/vpsdoctor-mcp/allowed_services.conf` en el VPS para listar los servicios que realmente quieres poder reiniciar (uno por línea — viene con `nginx` y `mariadb` como ejemplo).

### 2. Donde corra el servidor

```bash
git clone https://github.com/miguelmartt/vpsdoctor-mcp
cd vpsdoctor-mcp
pip install -e .
cp .env.example .env   # y edítalo
```

`.env`:

```
VPS_HOST=tu-ip-o-dominio-del-vps
VPS_PORT=22
VPS_USER=vpsdoctor-mcp
VPS_SSH_KEY_PATH=~/.ssh/vpsdoctor-mcp-key
SCRIPTS_DIR=/opt/vpsdoctor-mcp
ALLOWED_SERVICES=nginx,mariadb
```

### 3. Configura tu cliente MCP

Claude Desktop / Claude Code (`claude_desktop_config.json` o equivalente — ver [`examples/claude_desktop_config.json`](examples/claude_desktop_config.json)):

```json
{
  "mcpServers": {
    "vpsdoctor": {
      "command": "vpsdoctor-mcp",
      "env": {
        "VPS_HOST": "tu-ip-o-dominio-del-vps",
        "VPS_USER": "vpsdoctor-mcp",
        "VPS_SSH_KEY_PATH": "/ruta/absoluta/a/vpsdoctor-mcp-key",
        "SCRIPTS_DIR": "/opt/vpsdoctor-mcp",
        "ALLOWED_SERVICES": "nginx,mariadb"
      }
    }
  }
}
```

Cualquier otro cliente MCP que pueda lanzar un servidor por stdio funciona igual.

## Notas de seguridad

- La clave privada del usuario dedicado nunca debe salir de la máquina donde corre el servidor. `install.sh` la restringe en `authorized_keys` (sin pty, sin forwarding de puertos/agent/X11) y, mediante `sudoers`, a ejecutar solo los scripts de este repo — nada más, incluso si esa clave se filtrara alguna vez.
- El servidor rechaza claves de host SSH desconocidas (sin confiar a la primera). Si es la primera vez que te conectas a ese VPS desde donde corre el servidor, fija su clave de host antes: `ssh-keyscan -H tu-vps >> ~/.ssh/known_hosts`.
- Revisa [`scripts/`](scripts/) antes de instalar — son cortos y están pensados para leerse, no para confiar en ellos a ciegas.
- `vps_restart_service` y `vps_unban_ip` validan su entrada dos veces (una en Python, otra en el script de shell) antes de tocar nada, y cada reinicio/desbaneo ejecutado queda registrado en el log a nivel WARNING para tener rastro de auditoría.
- Este proyecto no recoge telemetría ni hace ninguna llamada de red aparte de la conexión SSH que tú configures.

## Cómo ampliarlo

Añade un script nuevo en `scripts/`, súmalo a la regla `sudoers` volviendo a ejecutar `install.sh`, y registra la herramienta correspondiente con `@mcp.tool()` en `src/vpsdoctor_mcp/server.py`. Los pull requests con nuevas comprobaciones de solo lectura son especialmente bienvenidos.

## Parte de la línea open source de VerticeDev

Proyecto hermano: [`vertice-automations`](https://github.com/miguelmartt/vertice-automations) (plantillas n8n reutilizables, incluida una versión por Telegram de esta misma idea de control de VPS).

## Licencia

MIT — ver [LICENSE](LICENSE).
