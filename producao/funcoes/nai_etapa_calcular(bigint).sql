CREATE OR REPLACE FUNCTION public.nai_etapa_calcular(p_contato bigint, OUT etapa text, OUT motivo text)
 RETURNS record
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_ids    bigint[] := nai_contato_irmaos(p_contato);
  v_chaves text[];
  v_vis    record;
  v_rec    timestamptz;
  v_cods   text;
  v_busca  timestamptz;
BEGIN
  SELECT array_agg(chave) INTO v_chaves FROM nai_contato WHERE id = ANY (v_ids);
  SELECT x.id, x.codigo, x.estado INTO v_vis FROM nai_visita x
   WHERE x.corretor_id = ANY (v_ids) AND nai_visita_aberta(x.estado) AND x.estado <> 'realizada'
   ORDER BY x.id DESC LIMIT 1;
  IF v_vis.id IS NOT NULL THEN
    etapa := 'agendamento_visita';
    motivo := 'visita #' || v_vis.id || ' do ' || v_vis.codigo || ' (' || v_vis.estado || ')';
    RETURN;
  END IF;
  SELECT max(e.primeiro_em), string_agg(DISTINCT e.codigo::text, ', ') INTO v_rec, v_cods
    FROM imovel_enviado_no_dia e WHERE e.chave = ANY (v_chaves) AND e.primeiro_em > now() - interval '7 days';
  -- as ultimas saidas pelo indice (contato_id, id DESC): o espelho do treino
  -- tem milhares de linhas, e varrer tudo a cada turno travava a abertura.
  SELECT greatest(v_rec, max(s.criado_em)) INTO v_rec
    FROM (SELECT x.criado_em, x.tipo, x.estado FROM nai_saida x
           WHERE x.contato_id = ANY (v_ids) ORDER BY x.id DESC LIMIT 300) s
   WHERE s.tipo = 'imagem' AND s.estado IN ('enviado', 'enviando', 'simulado')
     AND s.criado_em > now() - interval '7 days';
  -- pedido de busca DEPOIS do ultimo imovel recebido: no maximo os 12 turnos
  -- mais novos (a regex de busca e cara -- 694 turnos do espelho levaram 2 min).
  SELECT max(tt.criado_em) INTO v_busca
    FROM (SELECT t.criado_em, t.texto FROM nai_turno t
           WHERE t.contato_id = ANY (v_ids)
             AND t.criado_em > greatest(coalesce(v_rec, now() - interval '7 days'), now() - interval '7 days')
           ORDER BY t.id DESC LIMIT 12) tt
   WHERE coalesce((nai_pedido_de_perfil(coalesce(tt.texto, ''))->>'e_pedido')::boolean, false);
  IF v_rec IS NOT NULL AND (v_busca IS NULL OR v_busca < v_rec) THEN
    etapa := 'recebeu_imovel';
    motivo := 'recebeu ' || coalesce(v_cods, 'imóvel') || ' em ' || to_char(v_rec AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI');
    RETURN;
  END IF;
  etapa := 'identificacao';
  motivo := CASE WHEN v_busca IS NOT NULL THEN 'pediu opções' ELSE 'ainda não se sabe o que o cliente dele quer' END;
END;
$function$;
