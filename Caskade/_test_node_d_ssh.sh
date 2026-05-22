#!/bin/bash
for user in root ubuntu node_d; do
  for key in id_node_d id_node_d_new; do
    printf "Trying %s with %s: " "$user" "$key"
    ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/"$key" "${user}@78.17.134.17" 'echo OK' 2>/dev/null || echo 'FAIL'
  done
done
