UPDATE config_profiles
SET
    config = '{
  "log": { "loglevel": "info" },
  "observatory": {
    "subjectSelector": ["exit_node_remna", "exit_node_f"],
    "probeUrl": "https://cp.cloudflare.com/generate_204",
    "probeInterval": "30s",
    "enableBurst": true
  },
  "routing": {
    "domainStrategy": "AsIs",
    "balancers": [
      {
        "tag": "balancer_exit",
        "selector": ["exit_node_remna", "exit_node_f"],
        "strategy": {
          "type": "leastPing"
        },
        "fallbackTag": "exit_node_f"
      }
    ],
    "rules": [
      {
        "type": "field",
        "inboundTag": ["VLESS_YC_ENTRY"],
        "balancerTag": "balancer_exit"
      }
    ]
  },
  "inbounds": [
    {
      "tag": "VLESS_YC_ENTRY",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "127.0.0.1:4433",
          "show": false,
          "xver": 0,
          "shortIds": ["1a2b3c4d"],
          "privateKey": "SB1BD0THeV9Ravrbm3OWvc4-_jWlh7YRpEkztv_nUG8",
          "serverNames": ["alphaceiling23.ru"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "exit_node_remna",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "port": 2223,
            "address": "91.184.243.118",
            "users": [
              {
                "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
                "flow": "",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": { "network": "tcp" }
    },
    {
      "tag": "exit_node_f",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "port": 2223,
            "address": "193.233.137.187",
            "users": [
              {
                "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
                "flow": "",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": { "network": "tcp" }
    },
    { "tag": "DIRECT", "protocol": "freedom" },
    { "tag": "BLOCK", "protocol": "blackhole" }
  ]
}'::jsonb,
    updated_at = NOW()
WHERE name = 'YC-Entry-Cascade';
