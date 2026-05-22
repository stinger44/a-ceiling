-- =============================================================
-- Caskade VPN — Panel Setup SQL
-- Настройка Remnawave панели для каскадного VPN
--
-- Выполнять: docker exec -i remnawave-db psql -U postgres -d postgres < panel_setup.sql
-- =============================================================

-- ── 1. Удалить старый триггер принудительного порта (если есть) ──
DROP TRIGGER IF EXISTS trg_force_host_port ON hosts;
DROP FUNCTION IF EXISTS force_host_port();

-- ── 2. Создать/обновить профиль YC-Entry-Cascade ─────────────
-- Используется нодой node_e (YC белый список)
-- Входящий: VLESS Reality :443 для клиентов
-- Исходящий: VLESS plain → node_d:2223 (каскад)

INSERT INTO config_profiles (uuid, name, config, created_at, updated_at)
VALUES (
    gen_random_uuid(),
    'YC-Entry-Cascade',
    '{
        "log": {"loglevel": "warning"},
        "routing": {
            "domainStrategy": "AsIs",
            "rules": [
                {
                    "type": "field",
                    "inboundTag": ["VLESS_YC_ENTRY"],
                    "outboundTag": "cascade_to_node_d"
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
                "tag": "cascade_to_node_d",
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
            {"tag": "DIRECT", "protocol": "freedom"},
            {"tag": "BLOCK", "protocol": "blackhole"}
        ]
    }'::jsonb,
    NOW(),
    NOW()
)
ON CONFLICT (name)
DO UPDATE SET
    config = EXCLUDED.config,
    updated_at = NOW();

-- ── 3. Назначить профиль ноде yc white ───────────────────────
UPDATE nodes
SET active_config_profile_uuid = (
    SELECT uuid FROM config_profiles WHERE name = 'YC-Entry-Cascade'
)
WHERE name = 'yc white';

-- ── 4. Исправить порт в hosts для yc entry ───────────────────
UPDATE hosts SET port = 443 WHERE remark = 'yc entry';

-- ── 5. Проверка ───────────────────────────────────────────────
SELECT
    'nodes' AS table_name,
    n.name,
    n.address,
    cp.name AS profile
FROM nodes n
LEFT JOIN config_profiles cp ON cp.uuid = n.active_config_profile_uuid;

SELECT
    'hosts' AS table_name,
    remark,
    address,
    port
FROM hosts;

SELECT
    'profile_config' AS check_name,
    config::jsonb->'inbounds'->0->>'tag' AS inbound_tag,
    config::jsonb->'inbounds'->0->'streamSettings'->'realitySettings'->>'dest' AS reality_dest,
    config::jsonb->'outbounds'->0->>'protocol' AS outbound_proto,
    config::jsonb->'outbounds'->0->'settings'->'vnext'->0->>'address' AS outbound_addr,
    (config::jsonb->'outbounds'->0->'settings'->'vnext'->0->>'port')::int AS outbound_port
FROM config_profiles
WHERE name = 'YC-Entry-Cascade';
