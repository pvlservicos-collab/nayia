CREATE OR REPLACE FUNCTION public.nai_resultado_visita(p_turno bigint, p_codigo text, p_resultado text, p_obs text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v nai_visita; r text := lower(coalesce(p_resultado, ''));
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor.'::text; RETURN; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO v FROM nai_visita x
   WHERE x.corretor_id = k.id AND x.estado IN ('realizada', 'confirmada')
     AND (NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '') IS NULL
          OR x.codigo = NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '')::int)
   ORDER BY x.quando DESC LIMIT 1;
  IF v.id IS NULL THEN RETURN QUERY SELECT NULL::text, 'nao achei visita que ja tenha acontecido com ele.'::text; RETURN; END IF;

  UPDATE nai_visita SET resultado = r || coalesce(': ' || left(p_obs, 300), ''),
                        estado = 'encerrada', encerrada_em = now(), senha = NULL, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'resultado', r || coalesce(': ' || p_obs, ''));

  -- Fluxo v17 (Tel, 13/09): "Tel para fechar contratos ou sugerir outros
  -- imoveis" e FIM. O Tel recebe o que o corretor contou e a Nay para neste
  -- chat; o corretor nao recebe nada ("Que noticia boa" saiu, a pedido do Tel).
  PERFORM nai_avisar_tel(p_turno, v.id,
    CASE WHEN r ~ 'alug|fechar|quer|proposta'
         THEN 'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' (' || nai_fone_fmt(k.telefone) ||
              ') disse que o cliente QUER ALUGAR o ' || nai_ref_imovel(v.codigo) || '. É com você para fechar o contrato.'
         ELSE 'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' (' || nai_fone_fmt(k.telefone) ||
              ') contou como foi a visita no ' || nai_ref_imovel(v.codigo) || ': ' || replace(r, '_', ' ') || '.' END ||
    coalesce(E'\n"' || left(p_obs, 300) || '"', '') ||
    E'\nVisita #' || v.id || '. Parei de responder esse corretor: é com você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
    CASE WHEN r ~ 'alug|fechar|quer|proposta' THEN 'quer_alugar' ELSE 'resultado_visita' END);
  IF r ~ 'nao_foi|faltou|nao compareceu' THEN
    UPDATE corretores SET no_shows = coalesce(no_shows, 0) + 1 WHERE nai_chave(telefone) = k.chave;
  END IF;
  PERFORM nai_parar_chat(k.id, 'visita #' || v.id || ': resultado da visita (' || r || ')');
  RETURN QUERY SELECT NULL::text, 'foi para o Tel, que segue com ele. responda exatamente SILENCIO.'::text;
END;
$function$
;
