# context-lab42

This lab provides a ready-to-use cRPD (Juniper containerized routing daemon) infrastructure, operable via the official Junos MCP server. The goal is to prepare the environment so that Claude can interact directly with the routers through natural language — configuring, verifying, and troubleshooting — without touching the CLI.

> Friends don't let friends edit the CLI.

The lab is organized in two phases:

1. **Infrastructure preparation** (this file) — deploy the cRPD containers, wire the topology, enable NETCONF, and connect Claude Code to the Junos MCP server.
2. **Use cases** (separate files in [`use-cases/`](use-cases/)) — each use case deploys a specific network scenario end-to-end using the MCP. The first one is [EVPN-MPLS](use-cases/evpn-mpls.md).

---

## Topology

```
                        +---------+
                        |   R11   |
                        |  (CE)   |
                        +----+----+
                       /          \
                      /            \
             +-------+----+    +----+-------+
             |    R1      |    |    R2      |
             |  (PE)      +----+  (PE)      |
             +-------+----+    +----+-------+
                      \              /
                       \            /
                    +---+----------+---+
                    |        R3        |
                    |       (PE)       |
                    +--------+---------+
                             |
                        +----+----+
                        |   R12   |
                        |  (CE)   |
                        +---------+
```

| Router | Role |
|--------|------|
| R1     | PE   |
| R2     | PE   |
| R3     | PE   |
| R11    | CE   |
| R12    | CE   |

R1, R2, R3 form a full-mesh PE triangle. R11 is dual-homed on R1 and R2. R12 is single-homed on R3. Routing protocols, addressing, and services are defined per use case.

---

## Docker Infrastructure

### Networks

| Network    | Type   | Purpose                                                  |
|------------|--------|----------------------------------------------------------|
| `lab`      | bridge | Shared management segment — 192.168.100.0/24             |
| `net-r1-r2`| bridge | Dedicated R1↔R2 link (pure L2, IPs configured in Junos) |
| `net-r1-r3`| bridge | Dedicated R1↔R3 link (pure L2, IPs configured in Junos) |
| `net-r2-r3`| bridge | Dedicated R2↔R3 link (pure L2, IPs configured in Junos) |

### Interfaces per container

| Container | eth0 (lab)    | eth1           | eth2           |
|-----------|---------------|----------------|----------------|
| r1        | 192.168.100.2 | net-r1-r2 ↔ R2 | net-r1-r3 ↔ R3 |
| r2        | 192.168.100.3 | net-r1-r2 ↔ R1 | net-r2-r3 ↔ R3 |
| r3        | 192.168.100.4 | net-r1-r3 ↔ R1 | net-r2-r3 ↔ R2 |
| r11       | 192.168.100.5 | —              | —              |
| r12       | 192.168.100.6 | —              | —              |

eth0/eth1/eth2 appear inside Junos as `et-0/0/0`, `et-0/0/1`, `et-0/0/2` depending on the cRPD version. All routing IPs are configured in Junos (never on the Docker side).

---

## Prerequisites

- Ubuntu 22.04 LTS server
- Claude Code client (Mac/Windows/Linux)
- cRPD image: `junos-routing-crpd-docker-amd64-24.4R2-S3.5.tgz`
- Python 3.10+

---

## Step 1 — Install Docker on Ubuntu

Run on the **Ubuntu server**:

```bash
sudo apt remove -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
sudo rm -rf /var/lib/docker

sudo apt update && sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu jammy stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y \
  docker-ce=5:24.0.9-1~ubuntu.22.04~jammy \
  docker-ce-cli=5:24.0.9-1~ubuntu.22.04~jammy \
  containerd.io

sudo apt-mark hold docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER
newgrp docker
```

---

## Step 2 — Load the cRPD image

Copy the image to the server, then run:

```bash
docker load -i junos-routing-crpd-docker-amd64-24.4R2-S3.5.tgz
docker images | grep crpd
```

---

## Step 3 — Enable MPLS kernel modules

Run on the **Ubuntu server**:

```bash
sudo modprobe mpls_router
sudo modprobe mpls_iptunnel

# Persist across reboots
echo "mpls_router"   | sudo tee -a /etc/modules
echo "mpls_iptunnel" | sudo tee -a /etc/modules
```

Verify:

```bash
lsmod | grep mpls
# mpls_router, mpls_iptunnel, mpls_gso should appear
```

---

## Step 4 — Deploy the cRPD topology

Run on the **Ubuntu server**:

```bash
git clone https://github.com/lazabou/context-lab42.git
cd context-lab42
chmod +x deploy.sh destroy.sh
./deploy.sh
```

The script automatically creates:
- 4 Docker networks (`lab`, `net-r1-r2`, `net-r1-r3`, `net-r2-r3`)
- 5 cRPD containers (`r1`, `r2`, `r3`, `r11`, `r12`)
- PE-PE interface wiring (eth1/eth2 on R1, R2, R3)

Verify:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
# r1, r2, r3, r11, r12 should all show "Up"
```

To tear everything down:

```bash
./destroy.sh
```

---

## Step 5 — Access the routers

Run on the **Ubuntu server**:

```bash
docker exec -it r1  cli
docker exec -it r2  cli
docker exec -it r3  cli
docker exec -it r11 cli
docker exec -it r12 cli
```

---

## Step 6 — Enable SSH and NETCONF on the cRPD containers

SSH and NETCONF must be enabled on each router — this is what allows the Junos MCP server to connect to them later.

These commands are run **on the Ubuntu server** (not inside the router CLI). Each command pipes Junos CLI instructions directly into the container via `docker exec`:

```bash
for r in r1 r2 r3 r11 r12; do
  printf 'configure\nset system services ssh root-login allow\nset system services netconf ssh\ncommit\nexit\n' \
    | docker exec -i $r cli
done
```

What this does for each router:
- `configure` — enters Junos configuration mode
- `set system services ssh root-login allow` — allows SSH as root
- `set system services netconf ssh` — enables NETCONF over SSH (port 830)
- `commit` — applies the configuration
- `exit` — returns to operational mode

Verify on R1:

```bash
docker exec r1 cli -c 'show configuration system services'
# Expected output: netconf { ssh; } ssh { root-login allow; }
```

---

## Step 7 — Install the Junos MCP server (Juniper/junos-mcp-server)

Run on the **Ubuntu server**:

```bash
# Dependencies
sudo apt install -y python3-pip git

# Clone the official Juniper repo
git clone https://github.com/Juniper/junos-mcp-server.git ~/junos-mcp-server
cd ~/junos-mcp-server

# Fix pyparsing compatibility (required on Ubuntu 22.04)
pip3 install -r requirements.txt
pip3 install 'pyparsing>=3.0.0'
```

> **Note on pyparsing**: Ubuntu 22.04 ships with pyparsing 2.4.7, but `junos-eznc` (the underlying Junos Python library) requires version 3.0+. The second `pip3 install` command upgrades it.

---

## Step 8 — Configure the devices file

Create `~/junos-mcp-server/devices.json` on the **Ubuntu server**:

```json
{
    "r1":  { "ip": "192.168.100.2", "port": 22, "username": "root",
             "auth": { "type": "password", "password": "Poclab123!" } },
    "r2":  { "ip": "192.168.100.3", "port": 22, "username": "root",
             "auth": { "type": "password", "password": "Poclab123!" } },
    "r3":  { "ip": "192.168.100.4", "port": 22, "username": "root",
             "auth": { "type": "password", "password": "Poclab123!" } },
    "r11": { "ip": "192.168.100.5", "port": 22, "username": "root",
             "auth": { "type": "password", "password": "Poclab123!" } },
    "r12": { "ip": "192.168.100.6", "port": 22, "username": "root",
             "auth": { "type": "password", "password": "Poclab123!" } }
}
```

**Where do these IPs come from?**

The `lab` Docker bridge network was created with subnet `192.168.100.0/24` (see `deploy.sh`). Docker assigns IPs sequentially as containers join the network:
- `.1` is reserved for the Docker gateway
- `r1` → `.2`, `r2` → `.3`, `r3` → `.4`, `r11` → `.5`, `r12` → `.6`

You can confirm the actual IPs at any time:

```bash
docker inspect -f '{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
  r1 r2 r3 r11 r12
```

> **Security**: in production, use SSH keys instead of passwords.

---

## Step 9 — Start the MCP server

Run on the **Ubuntu server** (runs in the background):

```bash
cd ~/junos-mcp-server
nohup python3 jmcp.py -f devices.json -t streamable-http -H 0.0.0.0 \
  > ~/jmcp.log 2>&1 &

# Verify startup
sleep 3 && cat ~/jmcp.log
# Expected: "Streamable HTTP server started on http://0.0.0.0:30030"
```

The server exposes the MCP endpoint at `http://<SERVER_IP>:30030/mcp/`.

To restart after a reboot:

```bash
cd ~/junos-mcp-server && \
  nohup python3 jmcp.py -f devices.json -t streamable-http -H 0.0.0.0 \
  > ~/jmcp.log 2>&1 &
```

---

## Step 10 — Connect Claude to the Junos MCP

There are two Claude clients, each with a different MCP configuration mechanism:

| Client | MCP scope | Config file |
|--------|-----------|-------------|
| **Claude Code CLI** (`claude` in terminal) | Project-scoped | `.mcp.json` at repo root |
| **Claude Mac desktop app** | Global (all sessions) | `~/Library/Application Support/Claude/claude_desktop_config.json` |

Both work equally well for operating this lab — the only difference is scope.

---

### Option A — Claude Code CLI (project-scoped)

The file [`.mcp.json`](.mcp.json) at the root of this repo declares the Junos MCP server. Claude Code detects it automatically when you open a session from this directory:

```bash
cd context-lab42
claude
```

```json
{
  "mcpServers": {
    "junos-mcp": {
      "type": "http",
      "url": "http://localhost:30030/mcp/"
    }
  }
}
```

`junos-mcp` is only active in this project — it is invisible to other Claude Code sessions.

---

### Option B — Claude Mac desktop app (global)

The Mac desktop app does not read `.mcp.json`. MCP servers must be declared globally in:

```
~/Library/Application Support/Claude/claude_desktop_config.json
```

Add the `mcpServers` key alongside the existing `preferences`:

```json
{
  "mcpServers": {
    "junos-mcp": {
      "type": "http",
      "url": "http://localhost:30030/mcp/"
    }
  },
  "preferences": {
    ...
  }
}
```

**Restart the Claude app** after saving the file (Cmd+Q then relaunch).

> **Is global scope a problem?** Not really — the MCP only connects to this lab's routers and does nothing in unrelated sessions unless you explicitly ask about Junos. `CLAUDE.md` at the root of this repo also defines strict rules (MCP-only access, mandatory diff before commit, lab scope only) that Claude applies automatically when working in this project.

**If you are setting up on a new machine**, replace `localhost:30030` with your server IP if you are not using the SSH tunnel (see troubleshooting below).

---

### Troubleshooting: MCP unreachable from a corporate network

**Symptom:** TCP connectivity to port 30030 succeeds (`nc -zv <SERVER_IP> 30030` shows open), but Claude Code cannot connect to the MCP and the tools never appear. Direct `curl` to the MCP endpoint hangs with 0 bytes received.

**Root cause:** corporate transparent proxies intercept outbound HTTP connections on any port. They accept the TCP handshake and forward the HTTP POST, but silently drop or buffer streaming responses (Server-Sent Events / SSE), which is the format the MCP server uses to reply. Changing the port does not help — the proxy intercepts all HTTP traffic regardless of port.

**Solution: SSH tunnel**

Route MCP traffic through an encrypted SSH tunnel. The proxy cannot inspect SSH, so the responses flow through without interference.

**Step 1 — Update `.mcp.json` to point at localhost:**

```json
{
  "mcpServers": {
    "junos-mcp": {
      "type": "http",
      "url": "http://localhost:30030/mcp/"
    }
  }
}
```

**Step 2 — Make the MCP server a persistent systemd service on the Ubuntu server:**

```bash
sudo tee /etc/systemd/system/jmcp.service > /dev/null << 'EOF'
[Unit]
Description=Junos MCP Server
After=network.target

[Service]
Type=simple
User=<your_user>
WorkingDirectory=/home/<your_user>/junos-mcp-server
ExecStart=/usr/bin/python3 jmcp.py -f devices.json -t streamable-http -H 0.0.0.0 -p 30030
Restart=always
RestartSec=5
Environment=PATH=/home/<your_user>/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable jmcp
sudo systemctl start jmcp
```

Verify: `sudo systemctl is-active jmcp` should return `active`.

**Step 3 — Create a persistent SSH tunnel on your Mac (auto-start at login):**

Create `~/Library/LaunchAgents/com.lab42.ssh-tunnel-jmcp.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lab42.ssh-tunnel-jmcp</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ssh</string>
        <string>-N</string>
        <string>-o</string>
        <string>StrictHostKeyChecking=no</string>
        <string>-o</string>
        <string>ServerAliveInterval=30</string>
        <string>-o</string>
        <string>ServerAliveCountMax=3</string>
        <string>-L</string>
        <string>30030:localhost:30030</string>
        <string><your_user>@<SERVER_IP></string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardErrorPath</key>
    <string>/tmp/jmcp-tunnel.log</string>
</dict>
</plist>
```

> **SSH key authentication recommended.** The LaunchAgent above uses key-based SSH (no password prompt). Make sure your public key is in `~/.ssh/authorized_keys` on the server. If you need password auth, install `sshpass` via Homebrew and add it as the first argument.

Load the agent (no reboot needed):

```bash
launchctl load ~/Library/LaunchAgents/com.lab42.ssh-tunnel-jmcp.plist
```

**Step 4 — Verify the full chain:**

```bash
# Tunnel is active
launchctl list | grep lab42

# MCP responds via tunnel
curl -s --max-time 5 -X POST http://localhost:30030/mcp/ \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}},"id":1}'
# Expected: event: message / data: {"jsonrpc":"2.0","id":1,"result":{"serverInfo":...}}
```

Once both checks pass, restart Claude Code from the project directory — `junos-mcp` will appear in `/mcp` and the tools will be available.

**To stop the tunnel:**

```bash
launchctl unload ~/Library/LaunchAgents/com.lab42.ssh-tunnel-jmcp.plist
```

### Interaction rules — CLAUDE.md

The file [`CLAUDE.md`](CLAUDE.md) at the root of this repo defines strict rules that Claude follows automatically in this project:

- **MCP-only device access** — Claude uses exclusively the junos-mcp tools (`execute_junos_command`, `get_junos_config`, `load_and_commit_config`, `junos_config_diff`, `gather_device_facts`, `get_router_list`). It will never use bash, ssh, or docker exec to reach the routers.
- **Mandatory diff before commit** — before any `load_and_commit_config`, Claude must display the diff with `junos_config_diff` and wait for explicit confirmation.
- **Lab scope only** — the MCP server covers r1, r2, r3, r11, r12 only. Claude will not use it for other Junos devices.
- **MCP failure handling** — if the MCP server does not respond, Claude reports it and stops instead of falling back to a different access method.

Claude Code loads `CLAUDE.md` automatically at session start — no setup required.

### Verify the MCP is active

When Claude Code opens this project, run:

```
List the routers available in the lab
```

Claude should call `get_router_list` and return r1, r2, r3, r11, r12 — confirming the MCP is connected.

### How Claude uses the MCP tools

Once active, the tools are called automatically — no explicit invocation needed. Just describe what you want in natural language:

```
Show me the interfaces on R1
Check BGP sessions on all PE routers
Configure OSPF area 0 on R1, R2 and R3
```

**From claude.ai (web chat):** `.mcp.json` is specific to Claude Code (CLI and IDE extensions). It has no effect on the claude.ai web interface.

### Available MCP tools

| Tool                    | Description                              |
|-------------------------|------------------------------------------|
| `execute_junos_command` | Run a show command                       |
| `get_junos_config`      | Retrieve the current configuration       |
| `load_and_commit_config`| Push and commit a configuration          |
| `junos_config_diff`     | Compare candidate vs running config      |
| `gather_device_facts`   | System information for a router          |
| `get_router_list`       | List configured routers                  |

---

## Use Cases

Once the infrastructure is ready, use cases are run from the [`use-cases/`](use-cases/) directory. Each use case is self-contained: it describes the scenario, the expected topology, and the step-by-step configuration Claude applies via the MCP.

| Use case | Description |
|----------|-------------|
| [EVPN-MPLS](use-cases/evpn-mpls.md) | MPLS backbone with OSPF + LDP, EVPN service over the PE triangle |

---

## References

- [Juniper/junos-mcp-server](https://github.com/Juniper/junos-mcp-server) — Official Juniper MCP server
- [cRPD Deployment Guide](https://www.juniper.net/documentation/us/en/software/crpd/crpd-deployment/crpd-deployment.pdf) — Juniper documentation
- [Claude Code MCP](https://docs.anthropic.com/en/docs/claude-code/mcp) — MCP integration in Claude Code
