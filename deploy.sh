#!/bin/bash
set -e

CRPD_IMAGE="crpd:24.4R2-S3.5"
CONFIG_DIR="$(cd "$(dirname "$0")/configs" && pwd)"

echo "=== [1/4] Enabling MPLS kernel modules ==="
echo 'Poclab123!' | sudo -S modprobe mpls_router   2>/dev/null && echo "mpls_router OK"   || echo "mpls_router FAILED (non-fatal)"
echo 'Poclab123!' | sudo -S modprobe mpls_iptunnel 2>/dev/null && echo "mpls_iptunnel OK" || echo "mpls_iptunnel FAILED (non-fatal)"

echo ""
echo "=== [2/4] Creating Docker networks ==="
# Management / shared L2
docker network create --subnet 192.168.100.0/24 lab 2>/dev/null || echo "lab already exists"
# PE-PE dedicated L2 segments (IPs configured in Junos)
docker network create net-r1-r2 2>/dev/null || echo "net-r1-r2 already exists"
docker network create net-r1-r3 2>/dev/null || echo "net-r1-r3 already exists"
docker network create net-r2-r3 2>/dev/null || echo "net-r2-r3 already exists"

echo ""
echo "=== [3/4] Creating containers ==="
for name in r1 r2 r3 r11 r12; do
    HOSTNAME=$(echo $name | tr '[:lower:]' '[:upper:]')
    docker create --privileged --name $name \
        --network lab \
        -v "${CONFIG_DIR}/${name}:/config" \
        --hostname $HOSTNAME \
        ${CRPD_IMAGE}
    echo "$name created"
done

echo ""
echo "=== Wiring PE-PE interfaces (eth1, eth2) ==="
# R1: eth1=net-r1-r2  eth2=net-r1-r3
docker network connect net-r1-r2 r1
docker network connect net-r1-r3 r1
# R2: eth1=net-r1-r2  eth2=net-r2-r3
docker network connect net-r1-r2 r2
docker network connect net-r2-r3 r2
# R3: eth1=net-r1-r3  eth2=net-r2-r3
docker network connect net-r1-r3 r3
docker network connect net-r2-r3 r3

echo ""
echo "=== [4/4] Starting containers ==="
docker start r1 r2 r3 r11 r12

sleep 5
echo ""
echo "=== Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -v netbox

echo ""
echo "=== Access: docker exec -it <name> cli ==="
