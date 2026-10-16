-- teste da 378: cada conversa da conta proprietários sai com o anúncio dela
SELECT c.id, left(c.nome, 22) AS nome, x.codigo, x.negocio, left(x.titulo, 45) AS titulo, x.preco, left(x.foto, 60) AS foto, x.no_ar
  FROM privado.olx_chat c LEFT JOIN crm_olx_chats_anuncios('proprietarios') x ON x.list_id = c.list_id
 WHERE c.conta = 'proprietarios' ORDER BY c.id;
SELECT has_function_privilege('nay_disparo', 'public.crm_olx_chats_anuncios(text)', 'EXECUTE') AS crm_pode;
