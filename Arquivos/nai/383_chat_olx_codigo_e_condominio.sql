-- 383: o chat da OLX no CRM mostra o CÓDIGO e o CONDOMÍNIO do imóvel no topo da conversa
--
-- Pedro, 16/10/2026 (com o print da conversa da Michelle Rodrigues): "consegue colocar aqui o código e o nome do condomínio
-- já para eu saber qual é, pode ser nessa parte de cima que eu marquei". crm_olx_chats_anuncios (378) ganha 'condominio' e
-- 'bairro', do cadastro do imóvel. "Casa", "Apartamento em Via Pública" e afins no campo do condomínio são tipo, não nome:
-- ficam de fora (o mesmo filtro de site_imoveis_para_enviar).
-- O tipo de retorno muda: DROP + CREATE na mesma transação, com a permissão do CRM (nay_disparo) de novo. Enquanto o CRM
-- novo não sobe, o velho lê as colunas pelo nome e ignora as novas.
BEGIN;
SET LOCAL lock_timeout = '3s';

DROP FUNCTION IF EXISTS public.crm_olx_chats_anuncios(text);
CREATE FUNCTION public.crm_olx_chats_anuncios(p_conta text)
 RETURNS TABLE(list_id text, codigo integer, negocio text, titulo text, preco numeric, foto text, url text, no_ar boolean,
               condominio text, bairro text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (h.list_id)
         h.list_id, a.codigo, a.negocio, nullif(a.conteudo->>'subject', ''),
         CASE WHEN a.conteudo->>'price' ~ '^[0-9]+(\.[0-9]+)?$' THEN (a.conteudo->>'price')::numeric END,
         nullif(a.conteudo->'images'->>0, ''), a.url,
         a.estado = 'publicado' AND coalesce(a.olx_status, '') NOT IN ('deleted', 'expired', 'refused'),
         CASE WHEN nay_sem_acento(lower(btrim(coalesce(i.condominio_nome, ''))))
                   ~ '^(casa|apartamento|sala|loja|galpao|terreno|lote|kitnet|flat|studio|cobertura|predio|ponto|sitio|chacara)'
              THEN NULL ELSE nullif(btrim(i.condominio_nome), '') END,
         nullif(btrim(i.bairro), '')
    FROM privado.olx_chat h
    JOIN privado.olx_anuncio a ON a.list_id = h.list_id
    LEFT JOIN imoveis i ON i.codigo = a.codigo
   WHERE h.conta = p_conta AND h.list_id IS NOT NULL
   ORDER BY h.list_id, a.enviado_em DESC NULLS LAST, a.id DESC
$function$;

REVOKE ALL ON FUNCTION public.crm_olx_chats_anuncios(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_olx_chats_anuncios(text) TO nay_disparo;

COMMIT;
