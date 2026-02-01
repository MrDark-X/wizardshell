#!/usr/bin/env bash
set -euo pipefail

# ===============================================================
# Wizard Shell
# ---------------------------------------------------------------
# Browser-based SSH terminal using xterm.js + WebSockets + ssh2
#
# Features:
# - Web-accessible interactive terminal (xterm.js)
# - SSH-backed interactive shell (ssh2)
# - systemd-managed service
# - Dedicated Linux user with password + SSH keys
# - Optional sudo policy (FULL or LIMITED)
#
# Author:
#   Yaswanth Surya Chalamalasetty
#   CortexLab | Wizard Shell Project
#
# WARNING:
# - This tool exposes shell access via HTTP.
# - Deploy ONLY on trusted networks or behind authentication/HTTPS.
# ===============================================================

# =========================
# CONFIG (edit as needed)
# =========================
APP_NAME="Wizard Shell"
APP_USER="webterm"
APP_GROUP="webterm"
APP_DIR="/opt/wizard-shell"
SERVICE_NAME="wizard-shell"
APP_PORT="8088"

SSH_HOST="127.0.0.1"
SSH_PORT="22"
SSH_USER="${APP_USER}"
SSH_KEY_PATH="/home/${APP_USER}/.ssh/webterm_id_ed25519"

# SUDO MODE:
#   "full"    -> webterm can sudo anything (requires password)
#   "limited" -> only systemctl + journalctl
#   "none"    -> no sudo
SUDO_MODE="full"

# Packages
APT_PACKAGES=(openssh-server nodejs npm)

# Node dependencies
NPM_DEPS=(express ws ssh2 xterm)

# =========================
# Helpers
# =========================
log()  { echo -e "[+] $*"; }
warn() { echo -e "[!] $*" >&2; }
die()  { echo -e "[x] $*" >&2; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root: sudo bash $0"
  fi
}

banner() {
  clear || true
  cat <<BANNER

██╗    ██╗██╗███████╗ █████╗ ██████╗ ██████╗ 
██║    ██║██║╚══███╔╝██╔══██╗██╔══██╗██╔══██╗
██║ █╗ ██║██║  ███╔╝ ███████║██████╔╝██║  ██║
██║███╗██║██║ ███╔╝  ██╔══██║██╔══██╗██║  ██║
╚███╔███╔╝██║███████╗██║  ██║██║  ██║██████╔╝
 ╚══╝╚══╝ ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ 

                 🧙‍♂️  W I Z A R D   S H E L L  🧙‍♂️

A secure, browser-based SSH terminal powered by:
  • xterm.js (frontend)
  • WebSockets (transport)
  • ssh2 (Node.js backend)
  • systemd-managed service

This script will:
  ✓ Create a dedicated Linux user (${APP_USER})
  ✓ Prompt for a secure password
  ✓ Configure SSH key-based access
  ✓ Install Node.js + required dependencies
  ✓ Deploy a Web SSH Terminal on port ${APP_PORT}
  ✓ Register and start a systemd service
  ✓ Configure sudo access (mode: ${SUDO_MODE})

Author:
  Yaswanth Surya Chalamalasetty
  CortexLab | Wizard Shell Project

⚠️  SECURITY NOTE:
  This tool provides shell access via a browser.
  Deploy ONLY on trusted networks or behind authentication/HTTPS.

───────────────────────────────────────────────────────────────

BANNER
}

install_packages() {
  log "Updating apt cache..."
  apt-get update -y

  log "Installing packages: ${APT_PACKAGES[*]} ..."
  apt-get install -y "${APT_PACKAGES[@]}"
}

enable_ssh() {
  log "Enabling SSH service..."
  systemctl enable --now ssh 2>/dev/null || true
  systemctl enable --now sshd 2>/dev/null || true
  systemctl status ssh --no-pager 2>/dev/null || true
  systemctl status sshd --no-pager 2>/dev/null || true
}

create_user() {
  if id "${APP_USER}" &>/dev/null; then
    log "User '${APP_USER}' already exists."
  else
    log "Creating user '${APP_USER}'..."
    useradd -m -s /bin/bash "${APP_USER}"

    echo
    echo "=============================================="
    echo " Set password for user '${APP_USER}'"
    echo "=============================================="
    passwd "${APP_USER}"
    echo
  fi
}

configure_sudo() {
  case "${SUDO_MODE}" in
    full)
      log "Configuring FULL sudo for '${APP_USER}' (requires password)..."
      cat > "/etc/sudoers.d/${APP_USER}-full" <<SUDOEOF
${APP_USER} ALL=(ALL:ALL) ALL
SUDOEOF
      chmod 0440 "/etc/sudoers.d/${APP_USER}-full"
      visudo -cf "/etc/sudoers.d/${APP_USER}-full" >/dev/null
      log "Full sudo policy OK."
      ;;
    limited)
      log "Configuring LIMITED sudo for '${APP_USER}' (systemctl + journalctl only)..."
      cat > "/etc/sudoers.d/${APP_USER}-limited" <<SUDOEOF
${APP_USER} ALL=(ALL:ALL) /usr/bin/systemctl, /usr/bin/journalctl
SUDOEOF
      chmod 0440 "/etc/sudoers.d/${APP_USER}-limited"
      visudo -cf "/etc/sudoers.d/${APP_USER}-limited" >/dev/null
      log "Limited sudo policy OK."
      ;;
    none)
      warn "Sudo policy disabled (no sudo access for '${APP_USER}')."
      ;;
    *)
      die "Invalid SUDO_MODE='${SUDO_MODE}'. Use: full | limited | none"
      ;;
  esac
}

setup_ssh_keys() {
  log "Ensuring ${APP_USER} .ssh directory permissions..."
  install -d -m 700 -o "${APP_USER}" -g "${APP_GROUP}" "/home/${APP_USER}/.ssh"

  if [[ ! -f "${SSH_KEY_PATH}" ]]; then
    log "Generating SSH keypair for ${APP_USER}..."
    sudo -u "${APP_USER}" ssh-keygen -t ed25519 -f "${SSH_KEY_PATH}" -N ""
  else
    log "SSH key already exists at ${SSH_KEY_PATH}"
  fi

  log "Ensuring public key is present in authorized_keys..."
  local pubkey="${SSH_KEY_PATH}.pub"
  local auth_keys="/home/${APP_USER}/.ssh/authorized_keys"

  touch "${auth_keys}"
  chown "${APP_USER}:${APP_GROUP}" "${auth_keys}"
  chmod 600 "${auth_keys}"

  if ! grep -qF "$(cat "${pubkey}")" "${auth_keys}"; then
    cat "${pubkey}" >> "${auth_keys}"
    log "Public key appended to authorized_keys."
  else
    log "Public key already present in authorized_keys."
  fi
}

setup_app_dir() {
  log "Creating application directory: ${APP_DIR}"
  mkdir -p "${APP_DIR}"
  chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"

  if [[ ! -f "${APP_DIR}/package.json" ]]; then
    log "Initializing npm project..."
    sudo -u "${APP_USER}" bash -lc "cd '${APP_DIR}' && npm init -y"
  fi

  log "Installing npm dependencies..."
  sudo -u "${APP_USER}" bash -lc "cd '${APP_DIR}' && npm install ${NPM_DEPS[*]}"
}

write_frontend() {
  log "Writing frontend (public/index.html)..."
  mkdir -p "${APP_DIR}/public"

  cat > "${APP_DIR}/public/index.html" <<'HTML_EOF'
<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<title>Wizard Shell</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm/css/xterm.css" />
<style>
html, body { height:100%; width:100%; margin:0; background:#0b0f14; }
#terminal { height:100vh; width:100vw; }
.xterm { height:100%; width:100%; }
</style>
</head>
<body>
<div id="terminal"></div>

<script src="https://cdn.jsdelivr.net/npm/xterm/lib/xterm.js"></script>
<script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit/lib/xterm-addon-fit.js"></script>

<script>
const term = new Terminal({
  cursorBlink: true,
  fontSize: 14,
  scrollback: 5000
});

const fitAddon = new FitAddon.FitAddon();
term.loadAddon(fitAddon);

term.open(document.getElementById("terminal"));
fitAddon.fit();

const wsProto = location.protocol === "https:" ? "wss://" : "ws://";
const ws = new WebSocket(wsProto + location.host + "/ws");

ws.onopen = () => {
  term.writeln("🧙‍♂️ Wizard Shell connected. Starting session...");
  const dims = fitAddon.proposeDimensions();
  if (dims) ws.send(JSON.stringify({ type: "resize", cols: dims.cols, rows: dims.rows }));
};

ws.onmessage = (ev) => {
  term.write(ev.data);
};

ws.onclose = () => {
  term.writeln("\r\n[Disconnected]");
};

term.onData((data) => {
  if (ws.readyState === WebSocket.OPEN) ws.send(data);
});

window.addEventListener("resize", () => {
  fitAddon.fit();
  const dims = fitAddon.proposeDimensions();
  if (dims && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: "resize", cols: dims.cols, rows: dims.rows }));
  }
});
</script>
</body>
</html>
HTML_EOF
}

write_backend() {
  log "Writing backend (server.js)..."
  cat > "${APP_DIR}/server.js" <<'JS_EOF'
// Wizard Shell - server.js
// xterm.js (browser) -> WebSocket -> SSH (ssh2) -> Linux shell
// Supports terminal resize + welcome banner

const path = require("path");
const express = require("express");
const http = require("http");
const WebSocket = require("ws");
const { Client } = require("ssh2");
const fs = require("fs");

const app = express();
app.use(express.static(path.join(__dirname, "public")));

const server = http.createServer(app);
const wss = new WebSocket.Server({ server, path: "/ws" });

// ===== CONFIG =====
const SSH_HOST = "127.0.0.1";
const SSH_PORT = 22;
const SSH_USER = "webterm";
const SSH_PRIVATE_KEY_PATH = "/home/webterm/.ssh/webterm_id_ed25519";

const DEFAULT_COLS = 120;
const DEFAULT_ROWS = 30;

wss.on("connection", (ws) => {
  const conn = new Client();
  let streamRef = null;

  conn.on("ready", () => {
    conn.shell(
      { term: "xterm-256color", cols: DEFAULT_COLS, rows: DEFAULT_ROWS },
      (err, stream) => {
        if (err) {
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(`\r\n[SSH SHELL ERROR] ${err.message}\r\n`);
          }
          ws.close();
          conn.end();
          return;
        }

        streamRef = stream;

        // Wizard Shell welcome message (inside terminal)
        try {
          stream.write(
            "\r\n🧙‍♂️  Welcome to Wizard Shell\r\n" +
            "────────────────────────────\r\n" +
            `User: ${SSH_USER}\r\n` +
            `Host: ${SSH_HOST}\r\n\r\n` +
            "Authorized use only.\r\n" +
            "All actions may be logged.\r\n\r\n"
          );
        } catch {}

        // SSH -> Browser
        stream.on("data", (data) => {
          if (ws.readyState === WebSocket.OPEN) ws.send(data.toString("utf8"));
        });

        if (stream.stderr) {
          stream.stderr.on("data", (data) => {
            if (ws.readyState === WebSocket.OPEN) ws.send(data.toString("utf8"));
          });
        }

        stream.on("close", () => {
          try { ws.close(); } catch {}
          conn.end();
        });

        // Browser -> SSH (keystrokes) and resize handling
        ws.on("message", (msg) => {
          const text = msg.toString();

          // Resize JSON payload: {"type":"resize","cols":X,"rows":Y}
          if (text && text[0] === "{") {
            try {
              const obj = JSON.parse(text);
              if (
                obj &&
                obj.type === "resize" &&
                Number.isInteger(obj.cols) &&
                Number.isInteger(obj.rows) &&
                obj.cols > 0 &&
                obj.rows > 0 &&
                streamRef
              ) {
                // ssh2: setWindow(rows, cols, heightPx, widthPx)
                streamRef.setWindow(obj.rows, obj.cols, 0, 0);
                return;
              }
            } catch {
              // fall through to treat as input
            }
          }

          // Default: terminal input
          try {
            if (streamRef) streamRef.write(text);
          } catch {}
        });

        ws.on("close", () => {
          try { streamRef && streamRef.close(); } catch {}
          conn.end();
        });
      }
    );
  });

  conn.on("error", (e) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(`\r\n[SSH CONNECTION ERROR] ${e.message}\r\n`);
      ws.close();
    }
  });

  // Load private key
  let privateKey;
  try {
    privateKey = fs.readFileSync(SSH_PRIVATE_KEY_PATH, "utf8");
  } catch (e) {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(`\r\n[CONFIG ERROR] Cannot read SSH key at ${SSH_PRIVATE_KEY_PATH}\r\n`);
      ws.close();
    }
    return;
  }

  conn.connect({
    host: SSH_HOST,
    port: SSH_PORT,
    username: SSH_USER,
    privateKey,
  });
});

const PORT = process.env.PORT || 8088;
server.listen(PORT, "0.0.0.0", () => {
  console.log(`Wizard Shell running on http://0.0.0.0:${PORT}`);
});
JS_EOF

  chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"
}

write_systemd_unit() {
  log "Writing systemd unit: /etc/systemd/system/${SERVICE_NAME}.service"

  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Wizard Shell - Web SSH Terminal (xterm.js + ws + ssh2)
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${APP_DIR}
Environment=PORT=${APP_PORT}
ExecStart=/usr/bin/node ${APP_DIR}/server.js
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=${APP_DIR}

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
  log "Reloading systemd and starting service..."
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.service"

  log "Service status:"
  systemctl status "${SERVICE_NAME}.service" --no-pager || true
}

final_notes() {
  echo
  log "Done."
  echo "    Open: http://<server-ip>:${APP_PORT}/"
  echo "    Logs: journalctl -u ${SERVICE_NAME}.service -n 100 --no-pager"
  echo

  case "${SUDO_MODE}" in
    full)
      echo "NOTE:"
      echo " - '${APP_USER}' has FULL sudo access (password required)."
      ;;
    limited)
      echo "NOTE:"
      echo " - '${APP_USER}' has LIMITED sudo access:"
      echo "   /usr/bin/systemctl and /usr/bin/journalctl"
      ;;
    none)
      echo "NOTE:"
      echo " - '${APP_USER}' has NO sudo access."
      ;;
  esac
  echo
  echo "SECURITY REMINDER:"
  echo " - Consider reverse proxy + HTTPS + authentication before exposing publicly."
  echo
}

# =========================
# Main
# =========================
require_root
banner
install_packages
enable_ssh
create_user
configure_sudo
setup_ssh_keys
setup_app_dir
write_frontend
write_backend
write_systemd_unit
start_service
final_notes
