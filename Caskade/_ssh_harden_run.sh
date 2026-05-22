#!/bin/bash
for h in aesa remna; do
  scp /d/Gravity/Caskade/_ssh_harden.sh ${h}:/tmp/ssh_harden.sh
  ssh ${h} 'sudo bash /tmp/ssh_harden.sh && rm /tmp/ssh_harden.sh'
done
