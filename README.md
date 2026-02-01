![Linux](https://img.shields.io/badge/platform-Linux-blue)
![Node.js](https://img.shields.io/badge/runtime-Node.js-green)
![systemd](https://img.shields.io/badge/init-systemd-critical)
![Status](https://img.shields.io/badge/status-stable-brightgreen)

# 🧙‍♂️ Wizard Shell

**Wizard Shell** is a secure, browser-based SSH terminal that gives you real Linux shell access from a web UI.  
It is designed for **labs, internal operations, DevOps workflows, and controlled jump-host access** — without fake PTYs or brittle hacks.

Wizard Shell uses **xterm.js in the browser**, **WebSockets for transport**, and **real SSH sessions under the hood**.

---

## ✨ Features

- 🌐 Browser-based interactive SSH terminal
- 🔐 Real SSH backend (no pseudo shells)
- ⚙️ systemd-managed service (restart-safe)
- 👤 Dedicated Linux user (`webterm`)
- 🔑 SSH key-based authentication
- 🔒 Configurable sudo access:
  - Full sudo
  - Limited sudo
  - No sudo
- 🧙 Custom Wizard Shell banner (UI + terminal)
- 🧩 Minimal dependencies, easy to audit

---

# 🧠 Architecture Overview

Browser (xterm.js)
│
▼
WebSocket (ws)
│
▼
Node.js backend (ssh2)
│
▼
Linux SSH daemon
│
▼
Real shell (webterm user)


This means:
- Commands execute **exactly as they would over SSH**
- No command emulation
- No privilege confusion

---

## ⚠️ Security Notice

Wizard Shell provides **interactive shell access via HTTP**.

**Deploy only if at least one of the following is true:**
- The server is on a trusted internal network
- Access is restricted via firewall / VPN
- The service is behind HTTPS + authentication

If exposed publicly without protection, Wizard Shell is equivalent to a public SSH endpoint.

---

## 📦 Requirements

- Ubuntu Server 22.04 / 24.04 (recommended)
- Root access (for installation)
- Internet access (to install Node.js dependencies)

---

## 🚀 Quick Installation

Clone or copy the installer script:

```bash
git clone https://github.com/MrDark-X/wizardshell.git
cd wizardshell/
chmod +x xterm.sh
sudo ./xterm.sh
```

---
# ▶️ Running Wizard Shell

Once installed, the service is managed by systemd.

Check status
```bash
systemctl status wizard-shell.service
systemctl restart wizard-shell.service
journalctl -u wizard-shell.service -n 100 --no-pager
```
---

# 🌐 Accessing the Web Terminal

Open your browser:
```cpp
http://<server-ip>:8088
```

---
# 🛠️ Customization Ideas

Put Wizard Shell behind Nginx + HTTPS

Add HTTP basic auth or SSO

Bind service to internal IP only

Add session idle timeout

Enable command logging for audit trails

Package as an Ansible role
---

# 👨‍💻 Author

Yaswanth Surya Chalamalasetty
CortexLab
Wizard Shell Project
Built for learning, Labs and Secops Control

---
