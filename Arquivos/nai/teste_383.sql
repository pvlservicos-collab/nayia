SELECT c.id, left(c.nome, 20) AS nome, x.codigo, x.condominio, x.bairro, left(x.titulo, 40) AS titulo FROM privado.olx_chat c LEFT JOIN crm_olx_chats_anuncios(c.conta) x ON x.list_id = c.list_id ORDER BY c.id;
SELECT has_function_privilege('nay_disparo', 'public.crm_olx_chats_anuncios(text)', 'EXECUTE') AS crm_pode;
