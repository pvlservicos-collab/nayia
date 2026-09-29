-- 189 -- a conferência do CRM lê também a CAIXA DE SAÍDA da Nay (29/09/2026).
-- O registro `mensagens` só tem o que a Nay manda quando a Z-API devolve o eco
-- (fromMe). Às 17:14–17:18 de 29/09 a Z-API não devolveu o eco de 63 mensagens
-- (cards e fotos para 3 corretores): a Nay mandou, o corretor recebeu, e o CRM
-- nunca soube -- a conversa ficou como "sem resposta" (Pedro: "não está
-- contando as pessoas que eu respondo... fica gente como não respondido").
-- Agora o que saiu da caixa (`nai_saida` enviado, com o id da Z-API) e não tem
-- eco no registro entra na conferência do mesmo jeito. O id da Z-API é o mesmo
-- do eco, então quando o eco chega depois nada duplica.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.crm_mensagens_da_parceria(p_desde timestamp with time zone, p_ate timestamp with time zone DEFAULT now(), p_limite integer DEFAULT 2000)
 RETURNS TABLE(id integer, telefone text, nome text, direcao text, origem text, texto text, midia text, duracao integer, message_id text, criada_em timestamp with time zone, citado_id text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  SELECT * FROM (
    SELECT m.id, m.telefone, m.nome, m.direcao, m.origem, m.texto, coalesce(m.midia_url, m.audio_url),
           m.duracao_seg, m.message_id, m.criada_em, m.citado_id
      FROM mensagens m
     WHERE m.criada_em >= p_desde AND m.criada_em < coalesce(p_ate, now())
       AND coalesce(m.message_id, '') <> ''
    UNION ALL
    -- 189: o que a caixa da Nay mandou e o eco não trouxe
    SELECT (-s.id)::int, coalesce(nullif(s.telefone_final, ''), c.telefone, s.chave_destino), c.nome_whatsapp,
           'enviada', CASE WHEN s.tipo = 'imagem' THEN 'imagem' ELSE 'texto' END, s.texto, s.imagem_url,
           NULL::int, s.message_id, s.enviado_em, NULL::text
      FROM nai_saida s
      LEFT JOIN nai_contato c ON c.id = s.contato_id
     WHERE s.estado = 'enviado' AND coalesce(s.message_id, '') <> ''
       AND s.enviado_em >= p_desde AND s.enviado_em < coalesce(p_ate, now())
       AND NOT EXISTS (SELECT 1 FROM mensagens m2 WHERE m2.message_id = s.message_id)
  ) x
   ORDER BY x.criada_em, x.id
   LIMIT greatest(1, least(coalesce(p_limite, 2000), 5000))
$function$;

COMMIT;
