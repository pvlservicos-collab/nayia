CREATE OR REPLACE FUNCTION public.campanha_reservar(p_so_teste boolean DEFAULT false)
 RETURNS SETOF privado.campanha_contato
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  r privado.campanha_contato;
  v_teste text[] := coalesce((SELECT array_agg(right(regexp_replace(x, '\D', '', 'g'), 8))
                                FROM regexp_split_to_table(coalesce((SELECT valor FROM olx_config WHERE chave = 'whatsapp_teste'), ''), '[,;\s]+') x
                               WHERE length(regexp_replace(x, '\D', '', 'g')) >= 8), '{}');
  v_h int := coalesce(nullif(regexp_replace(coalesce((SELECT valor FROM olx_config WHERE chave = 'campanha_espera_conversa_h'), ''), '\D', '', 'g'), '')::int, 12);
  v_motivo text;
  v_quem text;
BEGIN
  FOR r IN SELECT * FROM campanha_contato c
            WHERE c.estado = 'liberada' AND (NOT p_so_teste OR c.tel8 = ANY (v_teste))
              AND (c.adiada_em IS NULL OR c.adiada_em < now() - interval '30 minutes')
            ORDER BY c.prioridade DESC, c.id
            FOR UPDATE SKIP LOCKED LOOP
    v_motivo := CASE
      WHEN r.tel8 = ANY (site_painel_internos()) AND NOT r.tel8 = ANY (v_teste) THEN 'número da casa, da equipe ou de teste'
      WHEN NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = ANY (r.codigos) AND i.status = 'Disponível' AND i.disponivel)
        THEN 'os imóveis não estão mais Disponíveis'
      WHEN EXISTS (SELECT 1 FROM campanha_contato o WHERE o.chave = r.chave AND o.id <> r.id AND o.enviada_em > now() - interval '7 days')
        THEN 'outra campanha falou com ele nos últimos 7 dias'
      WHEN EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = r.chave AND l.opt_out) THEN 'pediu para não receber' END;
    IF v_motivo IS NOT NULL THEN
      UPDATE campanha_contato SET estado = 'cancelada', erro = v_motivo, atualizado_em = now() WHERE id = r.id;
      INSERT INTO campanha_evento (contato, tipo, texto) VALUES (r.id, 'cancelada', v_motivo);
      CONTINUE;
    END IF;
    IF EXISTS (SELECT 1 FROM falou_conosco f WHERE f.chave = r.chave AND f.ultima_em > now() - make_interval(hours => v_h))
       AND NOT r.tel8 = ANY (v_teste) THEN
      UPDATE campanha_contato SET adiada_em = now(), adiada_motivo = 'conversou conosco nas últimas ' || v_h || ' h', atualizado_em = now()
       WHERE id = r.id;
      CONTINUE;
    END IF;
    -- NÃO FALAR POR CIMA DE OUTRA NAY. Corretor com a Nay da Parceria (nay_parceria) ou com a Nay Corretores
    -- (nay_corretores): sai, e a resposta dele é DELAS (a campanha só anota e avisa). A Nay de captação (nay_captacao)
    -- responde os botões do modelo e aplica no cadastro sozinha (321): só sai com campanha_com_nay_captacao = sim.
    -- Conversa em andamento com outra Nay, uma visita ou a equipe: espera.
    v_quem := campanha_quem_atende(r.id);
    IF v_quem IS NOT NULL AND v_quem NOT IN ('nay_parceria', 'nay_corretores')
       AND NOT (v_quem = 'nay_captacao' AND coalesce((SELECT valor FROM olx_config WHERE chave = 'campanha_com_nay_captacao'), 'nao') = 'sim') THEN
      UPDATE campanha_contato SET adiada_em = now(), atualizado_em = now(),
             adiada_motivo = CASE v_quem WHEN 'nay_captacao' THEN 'a Nay de captação responderia (e aplicaria no cadastro sozinha): campanha_com_nay_captacao = nao'
                                         ELSE 'outro atendimento em andamento: ' || v_quem END
       WHERE id = r.id;
      CONTINUE;
    END IF;
    UPDATE campanha_contato SET estado = 'enviando', adiada_motivo = NULL, outro_atende = v_quem, atualizado_em = now()
     WHERE id = r.id RETURNING * INTO r;
    RETURN NEXT r;
    RETURN;
  END LOOP;
END;
$function$;
