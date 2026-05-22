#!/bin/bash
echo "=== Проверяем SSH к каждому серверу ==="
for h in node_d aesa remna; do
  printf "%s: " "${h}"
  ssh -o BatchMode=yes -o ConnectTimeout=5 "${h}" 'echo OK' 2>&1 || echo "FAIL"
done
