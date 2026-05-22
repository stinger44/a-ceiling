-- =============================================================
-- update_cascade_balancer.sql
-- Добавляет балансировку нагрузки на entry ноде между
-- node_d (78.17.134.17:2223) и node_f (193.233.137.187:2223)
--
-- Xray balancer: round-robin между двумя outbounds
-- Выполнять: docker exec -i remnawave-db psql -U postgres -d postgres < update_cascade_balancer.sql
-- =============================================================

-- Обновить профиль YC-Entry-Cascade: добавить balancer
UPDATE config_profiles
SET
    config = '{
        "log": {"loglevel": "warning"},
        "routing": {
            "domainStrategy": "AsIs",
            "balancers": [
                {
                    "tag": "balancer_exit",
                    "selector": ["exit_node_d", "exit_node_f"],
                    "strategy": {
                        "type": "roundRobin"
                    }
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
                "tag": "exit_node_d",
                "protocol": "vless",
                "settings": {
                    "vnext": [{
                        "address": "78.17.134.17",
                        "port": 2223,
                        "users": [{
                            "id": "e8752e6b-bcdd-42fe-b81c-3ee430653ede",
                            "encryption": "none",
                            "flow": ""
                        }]
                    }]
                },
                "streamSettings": {"network": "tcp"}
            },
            {
                "tag": "exit_node_f",
                "protocol": "vless",
                "settings": {
                    "vnext": [{
                        "address": "193.233.137.187",
                        "port": 2223,
                        "users": [{
                            "id": "e8752e6b-bcdd-42fe-b81c-3ee430653ede",
                            "encryption": "none",
                            "flow": ""
                        }]
                    }]
                },
                "streamSettings": {"network": "tcp"}
            },
            {"tag": "DIRECT", "protocol": "freedom"},
            {"tag": "BLOCK", "protocol": "blackhole"}
        ]
    }'::jsonb,
    updated_at = NOW()
WHERE name = 'YC-Entry-Cascade';

-- Проверка результата
SELECT
    name,
    config->'routing'->'balancers'->0->>'tag'   AS balancer_tag,
    config->'routing'->'balancers'->0->'selector' AS balancer_selector,
    config->'outbounds'->0->>'tag'               AS outbound_1,
    config->'outbounds'->0->'settings'->'vnext'->0->>'address' AS addr_1,
    config->'outbounds'->1->>'tag'               AS outbound_2,
    config->'outbounds'->1->'settings'->'vnext'->0->>'address' AS addr_2
FROM config_profiles
WHERE name = 'YC-Entry-Cascade';
