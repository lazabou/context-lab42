#!/bin/bash
set -e

CRPD_IMAGE="crpd:24.4R2-S3.5"
CONFIG_DIR="$(cd "$(dirname "$0")/configs" && pwd)"

echo "=== Enabling MPLS kernel modules ==="
echo 'Poclab123!' | sudo -S modprobe mpls_router   2>/dev/null && echo "mpls_router OK"   || echo "mpls_router FAILED (non-fatal)"
echo 'Poclab123!' | sudo -S modprobe mpls_iptunnel 2>/dev/null && echo "mpls_iptunnel OK" || echo "mpls_iptunnel FAILED (non-fatal)"

echo ""
echo "=== Creating lab network ==="
docker network create --subnet 192.168.100.0/24 lab 2>/dev/null || echo "lab already exists"

echo ""
echo "=== Creating containers ==="
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
echo "=== Starting containers ==="
docker start r1 r2 r3 r11 r12

echo ""
echo "=== Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

echo ""
echo "=== Access: docker exec -it <name> cli ==="
