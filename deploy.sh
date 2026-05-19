#!/bin/bash
set -e

CRPD_IMAGE="crpd:24.4R2-S3.5"
CONFIG_DIR="$(cd "$(dirname "$0")/configs" && pwd)"

echo "=== Enabling MPLS kernel modules ==="
sudo modprobe mpls_router  2>/dev/null || true
sudo modprobe mpls_iptunnel 2>/dev/null || true
sudo sysctl -w net.mpls.conf.lo.input=1 2>/dev/null || true

echo "=== Creating Docker networks ==="
docker network create --subnet 192.168.100.0/24 mgmt        2>/dev/null || echo "mgmt already exists"
docker network create --subnet 10.0.12.0/30  net-r1-r2      2>/dev/null || echo "net-r1-r2 already exists"
docker network create --subnet 10.0.13.0/30  net-r1-r3      2>/dev/null || echo "net-r1-r3 already exists"
docker network create --subnet 10.0.23.0/30  net-r2-r3      2>/dev/null || echo "net-r2-r3 already exists"
docker network create --subnet 10.0.111.0/30 net-r1-r11     2>/dev/null || echo "net-r1-r11 already exists"
docker network create --subnet 10.0.211.0/30 net-r2-r11     2>/dev/null || echo "net-r2-r11 already exists"
docker network create --subnet 10.0.312.0/30 net-r3-r12     2>/dev/null || echo "net-r3-r12 already exists"

echo ""
echo "=== Creating containers (pre-wiring all interfaces before start) ==="

# R1 — eth0=mgmt eth1=r1-r2 eth2=r1-r3 eth3=r1-r11
docker create --privileged --name r1 \
  --network mgmt --ip 192.168.100.1 \
  -v "${CONFIG_DIR}/r1:/config" \
  --hostname R1 \
  ${CRPD_IMAGE}
docker network connect --ip 10.0.12.1  net-r1-r2  r1
docker network connect --ip 10.0.13.1  net-r1-r3  r1
docker network connect --ip 10.0.111.1 net-r1-r11 r1

# R2 — eth0=mgmt eth1=r1-r2 eth2=r2-r3 eth3=r2-r11
docker create --privileged --name r2 \
  --network mgmt --ip 192.168.100.2 \
  -v "${CONFIG_DIR}/r2:/config" \
  --hostname R2 \
  ${CRPD_IMAGE}
docker network connect --ip 10.0.12.2  net-r1-r2  r2
docker network connect --ip 10.0.23.1  net-r2-r3  r2
docker network connect --ip 10.0.211.1 net-r2-r11 r2

# R3 — eth0=mgmt eth1=r1-r3 eth2=r2-r3 eth3=r3-r12
docker create --privileged --name r3 \
  --network mgmt --ip 192.168.100.3 \
  -v "${CONFIG_DIR}/r3:/config" \
  --hostname R3 \
  ${CRPD_IMAGE}
docker network connect --ip 10.0.13.2  net-r1-r3  r3
docker network connect --ip 10.0.23.2  net-r2-r3  r3
docker network connect --ip 10.0.312.1 net-r3-r12 r3

# R11 — eth0=mgmt eth1=r1-r11 eth2=r2-r11
docker create --privileged --name r11 \
  --network mgmt --ip 192.168.100.11 \
  -v "${CONFIG_DIR}/r11:/config" \
  --hostname R11 \
  ${CRPD_IMAGE}
docker network connect --ip 10.0.111.2 net-r1-r11 r11
docker network connect --ip 10.0.211.2 net-r2-r11 r11

# R12 — eth0=mgmt eth1=r3-r12
docker create --privileged --name r12 \
  --network mgmt --ip 192.168.100.12 \
  -v "${CONFIG_DIR}/r12:/config" \
  --hostname R12 \
  ${CRPD_IMAGE}
docker network connect --ip 10.0.312.2 net-r3-r12 r12

echo ""
echo "=== Starting all containers ==="
docker start r1 r2 r3 r11 r12

echo ""
echo "=== Waiting for cRPD daemons to initialise (30s) ==="
sleep 30

echo ""
echo "=== Container status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

echo ""
echo "=== Done. Access routers with: docker exec -it <name> cli ==="
