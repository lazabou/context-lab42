#!/bin/bash

echo "=== Stopping and removing containers ==="
docker stop r1 r2 r3 r11 r12 2>/dev/null || true
docker rm   r1 r2 r3 r11 r12 2>/dev/null || true

echo "=== Removing lab network ==="
docker network rm lab 2>/dev/null || true

echo "=== Done ==="
