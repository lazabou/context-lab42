# context-lab42

MPLS L3VPN network lab based on cRPD (Juniper) containers, operated by Claude via the official Junos MCP server.

> Friends don't let friends edit the CLI.

---

## Logical Topology

```
                          AS 65011
                        +---------+
                        |   R11   |
                        |  (CE)   |
                        +----+----+
                       /          \
                      /            \
             +-------+----+    +----+-------+
             |    R1      |    |    R2      |
             |  PE        +----+  PE        |
             | lo:10.0.0.1|    | lo:10.0.0.2|
             |  AS 65000  |    |  AS 65000  |
             +-------+----+    +----+-------+
                      \              /
                       \            /
                    +---+----------+---+
                    |        R3        |
                    |  PE lo:10.0.0.3  |
                    |    AS 65000      |
                    +--------+---------+
                             |
                        +----+----+
                        |   R12   |
                        |  (CE)   |
                        | AS 65012|
                        +---------+
```

### Roles

| Router | Role      | Loopback      | AS    |
|--------|-----------|---------------|-------|
| R1     | PE        | 10.0.0.1/32   | 65000 |
| R2     | PE        | 10.0.0.2/32   | 65000 |
| R3     | PE        | 10.0.0.3/32   | 65000 |
| R11    | CE (VPN1) | 10.0.0.11/32  | 65011 |
| R12    | CE (VPN1) | 10.0.0.12/32  | 65012 |

### Target protocols (to be configured in Junos)

- **OSPF** area 0 — PE backbone IGP
- **LDP** — MPLS label distribution
- **iBGP** vpnv4 — full mesh between PEs (AS 65000)
- **eBGP** — PE↔CE (R11: AS 65011, R12: AS 65012)
- **VRF VPN1** — L3VPN connecting R11 and R12, RT 65000:1

---

## Docker Infrastructure

### Networks

| Network    | Type   | Purpose                                              |
|------------|--------|------------------------------------------------------|
| `lab`      | bridge | Shared L2 segment (mgmt + CE access) 192.168.100.0/24 |
| `net-r1-r2`| bridge | Dedicated R1↔R2 link (pure L2, IPs configured in Junos) |
| `net-r1-r3`| bridge | Dedicated R1↔R3 link (pure L2, IPs configured in Junos) |
| `net-r2-r3`| bridge | Dedicated R2↔R3 link (pure L2, IPs configured in Junos) |

### Interfaces per container

| Container | eth0 (lab)       | eth1           | eth2           |
|-----------|------------------|----------------|----------------|
| r1        | 192.168.100.2    | net-r1-r2 ↔ R2 | net-r1-r3 ↔ R3 |
| r2        | 192.168.100.3    | net-r1-r2 ↔ R1 | net-r2-r3 ↔ R3 |
| r3        | 192.168.100.4    | net-r1-r3 ↔ R1 | net-r2-r3 ↔ R2 |
| r11       | 192.168.100.5    | —              | —              |
| r12       | 192.168.100.6    | —              | —              |

All routing IPs are configured inside Junos. eth0/eth1/eth2 appear as `et-0/0/0`, `et-0/0/1`, `et-0/0/2` depending on the cRPD version.

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

The `lab` Docker bridge network was created with subnet `192.168.100.0/24` (see `deploy.sh`). Docker assigns IPs sequentially to containers as they join the network:
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

## Step 10 — Connect Claude Code to the Junos MCP

Create or edit `~/.claude/mcp.json` on your **Mac/PC client**:

```json
{
  "mcpServers": {
    "junos-mcp": {
      "type": "http",
      "url": "http://<SERVER_IP>:30030/mcp/"
    }
  }
}
```

Replace `<SERVER_IP>` with your Ubuntu server's IP address (e.g. `172.30.193.14`).

**Restart Claude Code** to load the MCP configuration.

### How Claude connects to the Junos MCP

Once `~/.claude/mcp.json` is saved and Claude Code is restarted, the MCP tools are available **immediately and automatically** — you do not need to ask Claude to "connect" or "activate" anything.

**From Claude Code (CLI or IDE extension):** Claude discovers the available MCP tools at startup. As soon as you describe a network task in natural language, Claude decides on its own whether to call a Junos MCP tool to answer or complete the task. No explicit invocation syntax needed — just describe what you want:

```
Show me the interfaces on R1
Configure OSPF area 0 on R1, R2 and R3
Check BGP sessions on all PE routers
Simulate a failure on the R1-R2 link and diagnose
```

**From claude.ai (web chat):** The `~/.claude/mcp.json` file is specific to the Claude Code CLI and IDE extensions. It has **no effect** on the claude.ai web interface, which has its own separate MCP configuration mechanism.

**How it works under the hood:** each time you send a message, Claude evaluates which tools are relevant. If the task involves Junos, it calls `execute_junos_command`, `load_and_commit_config`, etc. — the MCP server receives the call, opens a NETCONF session to the target router, executes the operation, and returns the result to Claude. The whole round-trip is transparent.

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

## References

- [Juniper/junos-mcp-server](https://github.com/Juniper/junos-mcp-server) — Official Juniper MCP server
- [cRPD Deployment Guide](https://www.juniper.net/documentation/us/en/software/crpd/crpd-deployment/crpd-deployment.pdf) — Juniper documentation
- [Claude Code MCP](https://docs.anthropic.com/en/docs/claude-code/mcp) — MCP integration in Claude Code
