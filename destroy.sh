#!/bin/bash

echo "=== Stopping and removing containers ==="
docker stop r1 r2 r3 r11 r12 2>/dev/null || true
docker rm   r1 r2 r3 r11 r12 2>/dev/null || true

echo "=== Removing networks ==="
docker network rm lab net-r1-r2 net-r1-r3 net-r2-r3 net-r1-r11 net-r2-r11 net-r3-r12 2>/dev/null || true

echo "=== Done ==="
