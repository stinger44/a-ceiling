UPDATE nodes
SET address = '111.88.249.82', updated_at = NOW()
WHERE id = 2 AND uuid = '1fe06f8f-2f9f-4656-ba83-56e920066959';

SELECT id, name, address, port, is_connected, updated_at FROM nodes WHERE id = 2;
