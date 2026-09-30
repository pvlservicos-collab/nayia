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
