#!/bin/bash
for user in t1lt ubuntu debian admin remna aesa node_d; do
  echo -n "Trying $user on aesa: "
  ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/aesa_server_key ${user}@193.233.137.187 -p 22222 'echo OK' 2>/dev/null || echo 'FAIL'
done
