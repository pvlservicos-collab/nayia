-- 171 -- o @lid da captação no CRM (29/09/2026). Pedro: "vê um bug no
-- WhatsApp captação, tá puxando id e não número".
--
-- O eco do DISPARO da captação para um dono que o WhatsApp endereça por LID
-- chega só com o LID. O CRM procurava o telefone em dois lugares -- o que ele
-- mesmo já viu (chat_lid) e identidade_lid (a Parceria) -- e o dono que nunca
-- respondeu não está em nenhum: viravam conversas com o LID no lugar do
-- telefone e do nome (12 na captação, de 4 pessoas).
--
-- Duas saídas novas:
--   * crm_telefone_do_lid também olha captacao_leads.chat_lid;
--   * crm_contato_da_mensagem(message_id): quem recebeu aquela mensagem --
--     a captação guarda o id de cada disparo (captacao_mensagens) e a Nay, o
--     de cada envio (nai_saida). É a resposta certa mesmo para LID nunca
--     visto: o eco traz o mesmo id da mensagem que nós mandamos.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.crm_telefone_do_lid(p_lid text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  SELECT coalesce(
    (SELECT nai_fone_br(i.telefone)
       FROM identidade_lid i
      WHERE regexp_replace(i.lid, '\D', '', 'g') = regexp_replace(coalesce(p_lid, ''), '\D', '', 'g')
        AND coalesce(i.telefone, '') <> ''
      ORDER BY i.criado_em DESC NULLS LAST
      LIMIT 1),
    -- 171: a captação aprende o LID de cada dono que responde
    (SELECT nai_fone_br(l.telefone)
       FROM captacao_leads l
      WHERE regexp_replace(coalesce(l.chat_lid, ''), '\D', '', 'g') = regexp_replace(coalesce(p_lid, ''), '\D', '', 'g')
        AND regexp_replace(coalesce(p_lid, ''), '\D', '', 'g') <> ''
        AND coalesce(l.telefone, '') <> ''
      ORDER BY l.atualizado_em DESC NULLS LAST
      LIMIT 1))
$function$;

CREATE OR REPLACE FUNCTION public.crm_contato_da_mensagem(p_message_id text)
 RETURNS TABLE(telefone text, nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  (SELECT nai_fone_br(l.telefone), nullif(btrim(l.nome), '')
     FROM captacao_mensagens m JOIN captacao_leads l ON l.id = m.lead_id
    WHERE m.message_id = p_message_id AND coalesce(p_message_id, '') <> '' AND coalesce(l.telefone, '') <> ''
    LIMIT 1)
  UNION ALL
  (SELECT nai_fone_br(c.telefone), coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(c.nome_whatsapp), ''))
     FROM nai_saida s
     JOIN LATERAL (SELECT c2.* FROM nai_contato c2
                    WHERE c2.id = ANY (nai_contato_irmaos(s.contato_id)) AND c2.chave !~ '^lid:' AND coalesce(c2.telefone, '') <> ''
                    ORDER BY c2.id LIMIT 1) c ON true
    WHERE s.message_id = p_message_id AND coalesce(p_message_id, '') <> ''
    LIMIT 1)
  LIMIT 1
$function$;

REVOKE ALL ON FUNCTION crm_contato_da_mensagem(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_contato_da_mensagem(text), crm_telefone_do_lid(text) TO nay_disparo;

COMMIT;
