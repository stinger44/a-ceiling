SELECT n.id, n.uuid, n.name, n.address, n.port, n.is_connected, n.is_disabled,
       cp.name AS profile_name
FROM nodes n
LEFT JOIN config_profiles cp ON cp.uuid = n.active_config_profile_uuid
ORDER BY n.id;
