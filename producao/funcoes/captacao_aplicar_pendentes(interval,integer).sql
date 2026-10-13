CREATE OR REPLACE FUNCTION public.captacao_aplicar_pendentes(p_silencio interval DEFAULT '00:15:00'::interval, p_limite integer DEFAULT 40)
 RETURNS TABLE(lead_id bigint, codigo integer, mudou jsonb, conferir text[])
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  r record;
  v jsonb;
BEGIN
  FOR r IN
    SELECT l.id
      FROM captacao_leads l
      LEFT JOIN LATERAL (SELECT a.situacao, a.valor_dito, a.contrato_dito, a.aplicado_em FROM captacao_aplicado a
                          WHERE a.lead_id = l.id ORDER BY a.id DESC LIMIT 1) u ON true
     WHERE l.situacao IS NOT NULL
       AND l.telefone_chave IS DISTINCT FROM nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'))
       AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'recebida'
                          AND m.criada_em > now() - p_silencio)
       AND (u.situacao IS NULL
            OR (u.situacao, coalesce(u.valor_dito, ''), coalesce(u.contrato_dito, ''))
               IS DISTINCT FROM (l.situacao, coalesce(l.valor_locacao_pedido, ''), coalesce(l.contrato_ate, ''))
            -- 361: o valor de venda ou a resposta dos 6% chegou depois da última passada
            OR (nullif(btrim(l.valor_venda_pedido), '') IS NOT NULL
                AND (l.atualizado_em > u.aplicado_em OR captacao_honorarios_depois_de(l.id, u.aplicado_em))))
     ORDER BY l.id
     LIMIT greatest(1, coalesce(p_limite, 40))
  LOOP
    BEGIN
      v := captacao_aplicar_ao_cadastro(r.id);
      IF v IS NOT NULL THEN
        lead_id := r.id; codigo := (v->>'codigo')::int; mudou := v->'mudou';
        conferir := ARRAY(SELECT jsonb_array_elements_text(v->'conferir'));
        RETURN NEXT;
      END IF;
    EXCEPTION WHEN OTHERS THEN   -- um imóvel travado por outra gravação não segura os demais: volta na próxima rodada
      lead_id := r.id; codigo := NULL; mudou := '{}'::jsonb; conferir := ARRAY['erro, tento de novo: ' || SQLERRM];
      RETURN NEXT;
    END;
  END LOOP;

  -- a foto chegou: o que a captação deixou "Disponível fora do site" por falta de foto entra no site
  FOR r IN
    UPDATE imoveis i SET publicado_no_site = true
     WHERE i.status = 'Disponível' AND i.disponivel AND NOT i.publicado_no_site AND NOT coalesce(i.bloqueado, false)
       AND NOT coalesce(i.e_parceiro, false) AND i.travado AND i.travado_motivo LIKE 'captação: o dono disse disponível%'
       AND EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo)
    RETURNING i.codigo
  LOOP
    INSERT INTO captacao_aplicado (lead_id, codigo, situacao, mudou)
    SELECT coalesce((SELECT l.id FROM captacao_leads l WHERE l.codigo = r.codigo::text ORDER BY l.id LIMIT 1), 0), r.codigo, 'disponivel',
           jsonb_build_object('publicado_no_site', jsonb_build_object('de', false, 'para', true, 'por', 'a foto chegou'));
    PERFORM imovel_mudanca_registrar(r.codigo, NULL, NULL, NULL,
              jsonb_build_object('publicado_no_site', jsonb_build_object('de', false, 'para', true)),
              jsonb_build_object('publicado_no_site', false), ARRAY['a foto chegou: o imóvel entrou no site']);
    lead_id := NULL; codigo := r.codigo; conferir := '{}';
    mudou := jsonb_build_object('publicado_no_site', jsonb_build_object('de', false, 'para', true, 'por', 'a foto chegou'));
    RETURN NEXT;
  END LOOP;
END
$function$;
