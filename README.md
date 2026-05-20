# context-lab42

Lab réseau MPLS L3VPN basé sur des containers cRPD (Juniper) pilotés par Claude via le MCP Junos officiel.

> Friends don't let friends edit the CLI.

---

## Topologie logique

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

### Rôles

| Router | Rôle      | Loopback      | AS    |
|--------|-----------|---------------|-------|
| R1     | PE        | 10.0.0.1/32   | 65000 |
| R2     | PE        | 10.0.0.2/32   | 65000 |
| R3     | PE        | 10.0.0.3/32   | 65000 |
| R11    | CE (VPN1) | 10.0.0.11/32  | 65011 |
| R12    | CE (VPN1) | 10.0.0.12/32  | 65012 |

### Protocoles cibles (à configurer dans Junos)

- **OSPF** area 0 — IGP backbone PE
- **LDP** — distribution des labels MPLS
- **iBGP** vpnv4 — full mesh entre PE (AS 65000)
- **eBGP** — PE↔CE (R11: AS 65011, R12: AS 65012)
- **VRF VPN1** — L3VPN reliant R11 et R12, RT 65000:1

---

## Infrastructure Docker

### Réseaux

| Réseau     | Type   | Usage                                      |
|------------|--------|--------------------------------------------|
| `lab`      | bridge | Segment L2 partagé (mgmt + CE) 192.168.100.0/24 |
| `net-r1-r2`| bridge | Lien dédié R1↔R2 (L2 pur, IPs dans Junos) |
| `net-r1-r3`| bridge | Lien dédié R1↔R3 (L2 pur, IPs dans Junos) |
| `net-r2-r3`| bridge | Lien dédié R2↔R3 (L2 pur, IPs dans Junos) |

### Interfaces par container

| Container | eth0 (lab)       | eth1           | eth2           |
|-----------|------------------|----------------|----------------|
| r1        | 192.168.100.2    | net-r1-r2 ↔ R2 | net-r1-r3 ↔ R3 |
| r2        | 192.168.100.3    | net-r1-r2 ↔ R1 | net-r2-r3 ↔ R3 |
| r3        | 192.168.100.4    | net-r1-r3 ↔ R1 | net-r2-r3 ↔ R2 |
| r11       | 192.168.100.5    | —              | —              |
| r12       | 192.168.100.6    | —              | —              |

Toutes les IPs de routage sont configurées dans Junos (eth0/eth1/eth2 vus comme `et-0/0/0`, `et-0/0/1`, `et-0/0/2` selon la version cRPD).

---

## Prérequis

- Serveur Ubuntu 22.04 LTS
- Client Claude Code (Mac/Windows/Linux)
- Image cRPD : `junos-routing-crpd-docker-amd64-24.4R2-S3.5.tgz`
- Python 3.10+

---

## Étape 1 — Installer Docker sur Ubuntu

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

## Étape 2 — Charger l'image cRPD

Copier l'image sur le serveur puis :

```bash
docker load -i junos-routing-crpd-docker-amd64-24.4R2-S3.5.tgz
docker images | grep crpd
```

---

## Étape 3 — Activer les modules MPLS du kernel

```bash
sudo modprobe mpls_router
sudo modprobe mpls_iptunnel

# Persistance au reboot
echo "mpls_router"   | sudo tee -a /etc/modules
echo "mpls_iptunnel" | sudo tee -a /etc/modules
```

Vérification :

```bash
lsmod | grep mpls
# mpls_router, mpls_iptunnel, mpls_gso doivent apparaître
```

---

## Étape 4 — Déployer la topologie cRPD

```bash
git clone https://github.com/lazabou/context-lab42.git
cd context-lab42
chmod +x deploy.sh destroy.sh
./deploy.sh
```

Le script crée automatiquement :
- 4 réseaux Docker (`lab`, `net-r1-r2`, `net-r1-r3`, `net-r2-r3`)
- 5 containers cRPD (`r1`, `r2`, `r3`, `r11`, `r12`)
- Le câblage des interfaces PE-PE (eth1/eth2 sur R1, R2, R3)

Vérification :

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
# r1, r2, r3, r11, r12 doivent être "Up"
```

Pour tout supprimer :

```bash
./destroy.sh
```

---

## Étape 5 — Accéder aux routeurs

```bash
docker exec -it r1  cli
docker exec -it r2  cli
docker exec -it r3  cli
docker exec -it r11 cli
docker exec -it r12 cli
```

---

## Étape 6 — Activer SSH et NETCONF sur les cRPD

À faire sur **chaque routeur** (nécessaire pour le MCP Junos) :

```bash
for r in r1 r2 r3 r11 r12; do
  printf 'configure\nset system services ssh root-login allow\nset system services netconf ssh\ncommit\nexit\n' \
    | docker exec -i $r cli
done
```

Vérification sur R1 :

```bash
docker exec r1 cli -c 'show configuration system services'
# Doit afficher : netconf { ssh; } ssh { root-login allow; }
```

---

## Étape 7 — Installer le MCP Junos (Juniper/junos-mcp-server)

Sur le serveur Ubuntu :

```bash
# Dépendances
sudo apt install -y python3-pip git

# Cloner le repo officiel Juniper
git clone https://github.com/Juniper/junos-mcp-server.git ~/junos-mcp-server
cd ~/junos-mcp-server

# Corriger la compatibilité pyparsing (requis sur Ubuntu 22.04)
pip3 install -r requirements.txt
pip3 install 'pyparsing>=3.0.0'
```

---

## Étape 8 — Configurer les devices

Créer `~/junos-mcp-server/devices.json` :

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

> **Sécurité** : en production, utiliser des clés SSH plutôt que des mots de passe.

---

## Étape 9 — Démarrer le MCP server

Sur le serveur Ubuntu (en arrière-plan) :

```bash
cd ~/junos-mcp-server
nohup python3 jmcp.py -f devices.json -t streamable-http -H 0.0.0.0 \
  > ~/jmcp.log 2>&1 &

# Vérifier le démarrage
sleep 3 && cat ~/jmcp.log
# Doit afficher : "Streamable HTTP server started on http://0.0.0.0:30030"
```

Le serveur expose l'endpoint MCP sur `http://<IP_SERVEUR>:30030/mcp/`.

Pour relancer après un reboot :

```bash
cd ~/junos-mcp-server && \
  nohup python3 jmcp.py -f devices.json -t streamable-http -H 0.0.0.0 \
  > ~/jmcp.log 2>&1 &
```

---

## Étape 10 — Connecter Claude Code au MCP Junos

Créer ou éditer `~/.claude/mcp.json` sur votre **Mac/PC client** :

```json
{
  "mcpServers": {
    "junos-mcp": {
      "type": "http",
      "url": "http://<IP_SERVEUR>:30030/mcp/"
    }
  }
}
```

Remplacer `<IP_SERVEUR>` par l'IP du serveur Ubuntu (ici `172.30.193.14`).

**Redémarrer Claude Code** pour charger le MCP.

---

## Utilisation avec Claude

Une fois le MCP connecté, Claude peut interagir directement avec les routeurs :

```
# Exemples de requêtes à Claude :
"Montre-moi les interfaces de R1"
"Configure OSPF area 0 sur R1, R2 et R3"
"Vérifie les sessions BGP sur tous les PE"
"Simule une panne sur le lien R1-R2 et diagnostique"
```

### Outils MCP disponibles

| Outil                   | Description                              |
|-------------------------|------------------------------------------|
| `execute_junos_command` | Exécuter une commande show               |
| `get_junos_config`      | Récupérer la configuration courante      |
| `load_and_commit_config`| Pousser et commiter une configuration    |
| `junos_config_diff`     | Comparer candidate vs running            |
| `gather_device_facts`   | Infos système du routeur                 |
| `get_router_list`       | Lister les routeurs configurés           |

---

## Références

- [Juniper/junos-mcp-server](https://github.com/Juniper/junos-mcp-server) — MCP officiel Juniper
- [cRPD Deployment Guide](https://www.juniper.net/documentation/us/en/software/crpd/crpd-deployment/crpd-deployment.pdf) — Documentation Juniper
- [Claude Code MCP](https://docs.anthropic.com/en/docs/claude-code/mcp) — Intégration MCP dans Claude Code
