-- 378 -- O CHAT DA OLX NO CRM COM O ANÚNCIO DE CADA CONVERSA
--
-- Pedro, 16/10/2026: "quero que refaça o chat da olx do crm para ser igual o da olx normal em estrutura, e
-- informações". No chat da OLX cada conversa mostra a foto do anúncio, o título e o preço; o webhook da OLX só traz
-- o listId (e nome, e-mail e telefone de quem escreveu). O anúncio está em privado.olx_anuncio (o que o nay-olx
-- publicou): conteudo->>'subject' é o título na OLX, conteudo->>'price' o preço e conteudo->'images'->>0 a capa.
-- Função nova, só de leitura, para o papel do CRM (nay_disparo), como as outras crm_olx_* (314, 369).
-- `no_ar`: o anúncio continua publicado; a tela manda para "Conversas inativas" a conversa cujo anúncio saiu.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.crm_olx_chats_anuncios(p_conta text)
 RETURNS TABLE(list_id text, codigo integer, negocio text, titulo text, preco numeric, foto text, url text, no_ar boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (h.list_id)
         h.list_id, a.codigo, a.negocio, nullif(a.conteudo->>'subject', ''),
         CASE WHEN a.conteudo->>'price' ~ '^[0-9]+(\.[0-9]+)?$' THEN (a.conteudo->>'price')::numeric END,
         nullif(a.conteudo->'images'->>0, ''), a.url,
         a.estado = 'publicado' AND coalesce(a.olx_status, '') NOT IN ('deleted', 'expired', 'refused')
    FROM privado.olx_chat h
    JOIN privado.olx_anuncio a ON a.list_id = h.list_id
   WHERE h.conta = p_conta AND h.list_id IS NOT NULL
   ORDER BY h.list_id, a.enviado_em DESC NULLS LAST, a.id DESC
$function$;

REVOKE ALL ON FUNCTION public.crm_olx_chats_anuncios(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_olx_chats_anuncios(text) TO nay_disparo;

COMMIT;
