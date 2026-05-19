# context-lab42

A collaborative playground for experimenting with:
- Model Context Protocol (MCP)
- Junos automation
- Context-driven network workflows

> Friends don't let friends edit the CLI.

---

## Topology

```
                          AS 65011
                        +---------+
                        |   R11   | 192.168.100.5
                        |  (CE)   |
                        +----+----+
                       /          \
                      /            \
             +-------+----+    +----+-------+
             |    R1      |    |    R2      |
  .100.2     |  PE        +----+  PE        |     .100.3
             | AS 65000   |    | AS 65000   |
             +-------+----+    +----+-------+
                      \              /
                       \            /
                    +---+----------+---+
                    |        R3        |
                    |       PE         |  192.168.100.4
                    |    AS 65000      |
                    +--------+---------+
                             |
                        +----+----+
                        |   R12   | 192.168.100.6
                        |  (CE)   |
                        | AS 65012|
                        +---------+

  All routers connected on a single L2 bridge (192.168.100.0/24).
  Logical topology (IPs, MPLS, VRFs) configured in Junos.
```

### Roles

| Router | Role       | Loopback       | AS    |
|--------|------------|----------------|-------|
| R1     | PE         | 1.1.1.1/32     | 65000 |
| R2     | PE         | 2.2.2.2/32     | 65000 |
| R3     | PE         | 3.3.3.3/32     | 65000 |
| R11    | CE (VPN1)  | 11.11.11.11/32 | 65011 |
| R12    | CE (VPN1)  | 12.12.12.12/32 | 65012 |

### Docker networking

Single flat L2 bridge (`lab` network, 192.168.100.0/24).  
All containers share one Ethernet segment — IP addressing and topology are configured directly in Junos.

| Container | Docker IP (eth0) |
|-----------|-----------------|
| r1        | 192.168.100.2   |
| r2        | 192.168.100.3   |
| r3        | 192.168.100.4   |
| r11       | 192.168.100.5   |
| r12       | 192.168.100.6   |

---

## Intended protocols (to configure in Junos)

- **OSPF** (area 0) — IGP on PE backbone (R1, R2, R3)
- **LDP** — MPLS label distribution on PE backbone
- **iBGP** (vpnv4) — full mesh between PE routers, AS 65000
- **eBGP** — PE↔CE (R11: AS 65011, R12: AS 65012)
- **VRF VPN1** — L3VPN connecting R11 and R12, RT 65000:1

---

## Prerequisites

### 1. Install Docker (Ubuntu 22.04)

```bash
sudo apt remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker
sudo apt update && sudo apt install ca-certificates curl gnupg -y
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu jammy stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install docker-ce=5:24.0.9-1~ubuntu.22.04~jammy docker-ce-cli=5:24.0.9-1~ubuntu.22.04~jammy containerd.io
sudo apt-mark hold docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER
```

### 2. Load cRPD image

```bash
docker load -i junos-routing-crpd-docker-amd64-24.4R2-S3.5.tgz
```

### 3. Enable MPLS kernel modules

```bash
sudo modprobe mpls_router
sudo modprobe mpls_iptunnel
echo "mpls_router" | sudo tee -a /etc/modules
echo "mpls_iptunnel" | sudo tee -a /etc/modules
```

---

## Deploy

```bash
git clone https://github.com/lazabou/context-lab42.git
cd context-lab42
chmod +x deploy.sh destroy.sh
./deploy.sh
```

## Destroy

```bash
./destroy.sh
```

## Access a router

```bash
docker exec -it r1 cli
docker exec -it r2 cli
docker exec -it r3 cli
docker exec -it r11 cli
docker exec -it r12 cli
```
