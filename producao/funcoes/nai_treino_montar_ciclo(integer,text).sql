CREATE OR REPLACE FUNCTION public.nai_treino_montar_ciclo(p_tamanho integer DEFAULT 50, p_rotulo text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_ciclo bigint;
  v_n     int;
BEGIN
  IF p_tamanho < 1 OR p_tamanho > 500 THEN
    RAISE EXCEPTION 'tamanho fora da faixa (1..500): %', p_tamanho;
  END IF;

  INSERT INTO nai_treino_ciclo (rotulo, tamanho)
  VALUES (coalesce(p_rotulo, 'ciclo de ' || p_tamanho), p_tamanho)
  RETURNING id INTO v_ciclo;

  INSERT INTO nai_treino_caso (
    ciclo_id, turno_origem, contato_origem, papel, quando_original,
    ele_disse, ela_respondeu_antes, ferramentas_antes, contexto)
  SELECT v_ciclo, p.turno_id, p.contato_id, p.papel, p.criado_em,
         p.ele_disse, p.ela_respondeu, p.ferramentas,
         nai_treino_contexto(p.contato_id, p.criado_em, 10)
    FROM (SELECT * FROM nai_treino_pool ORDER BY turno_id DESC LIMIT p_tamanho) p;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'o pool esta vazio -- todos os turnos respondidos ja viraram caso';
  END IF;

  -- o tamanho real pode ser menor que o pedido no ultimo ciclo
  UPDATE nai_treino_ciclo SET tamanho = v_n WHERE id = v_ciclo;
  RETURN v_ciclo;
END;
$function$;
