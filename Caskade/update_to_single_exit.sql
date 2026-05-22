DELETE FROM nodes WHERE name = 'aesa exit';

UPDATE config_profiles 
SET config = '{
  "log": {"loglevel": "info"},
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["VLESS_YC_ENTRY"],
        "outboundTag": "exit_node_remna"
      }
    ],
    "domainStrategy": "AsIs"
  },
  "inbounds": [
    {
      "tag": "VLESS_YC_ENTRY",
      "port": 443,
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]},
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
            "users": [
              {
                "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
                "flow": "",
                "encryption": "none"
              }
            ],
            "address": "91.184.243.118"
          }
        ]
      },
      "streamSettings": {"network": "tcp"}
    },
    {"tag": "DIRECT", "protocol": "freedom"},
    {"tag": "BLOCK", "protocol": "blackhole"}
  ]
}'
WHERE name = 'YC-Entry-Cascade';
