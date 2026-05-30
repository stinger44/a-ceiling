-- 1. Insert the user "ru-entry-node"
INSERT INTO users (
    uuid, short_uuid, username, status, traffic_limit_bytes, traffic_limit_strategy,
    expire_at, trojan_password, vless_uuid, ss_password, created_at, updated_at, hwid_device_limit
) VALUES (
    '1cc78261-2a77-49af-b178-c6e3d2c36c58',
    'ruentrynode12345',
    'ru-entry-node',
    'ACTIVE',
    0,
    'NO_RESET',
    '2099-12-31 23:59:59',
    'ru-entry-node-trojan-pass-12345',
    '1cc78261-2a77-49af-b178-c6e3d2c36c58',
    'ru-entry-node-ss-pass-12345',
    NOW(), NOW(),
    0
) ON CONFLICT (uuid) DO NOTHING;

-- 2. Add the user to Default-Squad
INSERT INTO internal_squad_members (internal_squad_uuid, user_id)
SELECT 'bef40c3a-0d81-41ff-895c-fe9f60826792', t_id 
FROM users 
WHERE username = 'ru-entry-node'
ON CONFLICT (internal_squad_uuid, user_id) DO NOTHING;

-- 3. Map CASCADE_FROM_RU inbound to Default-Squad
INSERT INTO internal_squad_inbounds (internal_squad_uuid, inbound_uuid)
VALUES ('bef40c3a-0d81-41ff-895c-fe9f60826792', '1678c4df-0a6d-4e93-88cf-566a06da951f')
ON CONFLICT (internal_squad_uuid, inbound_uuid) DO NOTHING;
