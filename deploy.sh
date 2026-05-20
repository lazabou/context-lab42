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
# PE-PE dedicated L2 segments (pure L2 — Docker IPs will be flushed after container start)
docker network create net-r1-r2  2>/dev/null || echo "net-r1-r2 already exists"
docker network create net-r1-r3  2>/dev/null || echo "net-r1-r3 already exists"
docker network create net-r2-r3  2>/dev/null || echo "net-r2-r3 already exists"
# PE-CE dedicated L2 segments
docker network create net-r1-r11 2>/dev/null || echo "net-r1-r11 already exists"
docker network create net-r2-r11 2>/dev/null || echo "net-r2-r11 already exists"
docker network create net-r3-r12 2>/dev/null || echo "net-r3-r12 already exists"

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
echo "=== [4/4] Starting containers ==="
# IMPORTANT: all docker network connect calls happen AFTER start.
# Docker assigns eth names in the ORDER of connect calls on a running container.
# Connecting before start causes alphabetical ordering (net-r1-r11 < net-r1-r2),
# which puts the CE network on eth1 instead of the PE-PE network.
docker start r1 r2 r3 r11 r12

sleep 5

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
echo "=== Wiring PE-CE interfaces (eth3 on PEs, eth1/eth2 on CEs) ==="
# R1: eth3=net-r1-r11  R11: eth1=net-r1-r11
docker network connect net-r1-r11 r1
docker network connect net-r1-r11 r11
# R2: eth3=net-r2-r11  R11: eth2=net-r2-r11
docker network connect net-r2-r11 r2
docker network connect net-r2-r11 r11
# R3: eth3=net-r3-r12  R12: eth1=net-r3-r12
docker network connect net-r3-r12 r3
docker network connect net-r3-r12 r12

sleep 2

echo ""
echo "=== Flushing Docker-assigned IPs from PE-PE and PE-CE interfaces ==="
# Docker assigns IPs via its IPAM — remove them so Junos owns these interfaces exclusively
for r in r1 r2 r3; do
    docker exec $r ip -4 addr flush dev eth1 2>/dev/null && echo "$r eth1: flushed" || echo "$r eth1: flush skipped"
    docker exec $r ip -4 addr flush dev eth2 2>/dev/null && echo "$r eth2: flushed" || echo "$r eth2: flush skipped"
    docker exec $r ip -4 addr flush dev eth3 2>/dev/null && echo "$r eth3: flushed" || echo "$r eth3: flush skipped"
done
docker exec r11 ip -4 addr flush dev eth1 2>/dev/null && echo "r11 eth1: flushed" || echo "r11 eth1: flush skipped"
docker exec r11 ip -4 addr flush dev eth2 2>/dev/null && echo "r11 eth2: flushed" || echo "r11 eth2: flush skipped"
docker exec r12 ip -4 addr flush dev eth1 2>/dev/null && echo "r12 eth1: flushed" || echo "r12 eth1: flush skipped"

echo ""
echo "=== Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -v netbox

echo ""
echo "=== Access: docker exec -it <name> cli ==="
