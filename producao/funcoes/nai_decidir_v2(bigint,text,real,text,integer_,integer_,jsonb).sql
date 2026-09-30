CREATE OR REPLACE FUNCTION public.nai_decidir_v2(p_turno bigint, p_intencao text, p_confianca real, p_por text, p_pedidos integer[] DEFAULT '{}'::integer[], p_rejeitados integer[] DEFAULT '{}'::integer[], p_bruto jsonb DEFAULT NULL::jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_piso real := coalesce(nullif(nai_cfg('v2_piso_intencao','0.60'),''),'0.60')::real;
  v_int  text;
  v_contato bigint;
BEGIN
  SELECT contato_id INTO v_contato FROM nai_turno WHERE id = p_turno;
  IF v_contato IS NULL THEN
    RAISE EXCEPTION 'turno % nao existe', p_turno;
  END IF;

  v_int := lower(btrim(coalesce(p_intencao, '')));
  IF v_int NOT IN ('pedir_imovel','rejeitar_imovel','pergunta_sobre_imovel','visita',
                   'resultado_visita','cortesia','oferta_de_imovel','assunto_geral') THEN
    v_int := 'indefinida';
  END IF;

  -- o piso so vale para o que o classificador decidiu; regra explicita
  -- (por='regra') nao tem confianca e nao cai aqui
  IF p_por IN ('jev','reserva_gpt') AND coalesce(p_confianca, 0) < v_piso THEN
    v_int := 'indefinida';
  END IF;

  INSERT INTO nai_turno_decisao (turno_id, intencao, decidido_por, confianca,
                                 codigos_pedidos, codigos_rejeitados, jev_bruto)
  VALUES (p_turno, v_int, coalesce(p_por,'jev'), p_confianca,
          coalesce(p_pedidos,'{}'), coalesce(p_rejeitados,'{}'), p_bruto)
  ON CONFLICT (turno_id) DO UPDATE SET
    intencao = EXCLUDED.intencao, decidido_por = EXCLUDED.decidido_por,
    confianca = EXCLUDED.confianca, codigos_pedidos = EXCLUDED.codigos_pedidos,
    codigos_rejeitados = EXCLUDED.codigos_rejeitados, jev_bruto = EXCLUDED.jev_bruto;

  -- a rejeicao entra no estado NA HORA, nao no fim do turno: o resto do
  -- turno ja precisa saber que aquele imovel esta fora
  IF coalesce(array_length(p_rejeitados,1),0) > 0 THEN
    PERFORM nai_estado_gravar_v2(v_contato, NULL, NULL, '{}', p_rejeitados, NULL, NULL, NULL);
  END IF;

  RETURN v_int;
END;
$function$;
