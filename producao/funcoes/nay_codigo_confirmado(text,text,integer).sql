CREATE OR REPLACE FUNCTION public.nay_codigo_confirmado(p_telefone text, p_codigo text, p_horas integer DEFAULT 48)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_tel  text := right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),8);
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  v_n    int;
  v_um   text;
BEGIN
  IF v_cod IS NULL OR length(v_tel) < 8 THEN
    RETURN 'nao';
  END IF;

  -- PROVA FORTE: ele escreveu o código. `nay_codigos_citados` já tira os
  -- valores ("paga até 4000" não é o imóvel 4000).
  IF EXISTS (
    SELECT 1 FROM mensagens m
     WHERE right(regexp_replace(m.telefone,'[^0-9]','','g'),8) = v_tel
       AND m.criada_em > now() - make_interval(hours => greatest(p_horas,1))
       AND v_cod = ANY(nay_codigos_citados(coalesce(m.texto,'') || ' ' || coalesce(m.citado,'')))
  ) THEN
    RETURN 'dito_por_ele';
  END IF;

  -- PROVA FRACA MAS SUFICIENTE: a Nay mandou UM card só para ele na
  -- janela, e é esse. Com dois ou mais, "esse" é ambíguo e ela pergunta --
  -- é o mesmo critério do `nay_imovel_do_disparo`, mas olhando ESTA
  -- conversa, que é evidência muito melhor que o disparo em grupo.
  SELECT count(DISTINCT e.codigo), min(e.codigo) INTO v_n, v_um
    FROM envios e
   WHERE e.destino = 'corretor'
     AND right(regexp_replace(e.telefone,'[^0-9]','','g'),8) = v_tel
     AND e.enviado_em > now() - make_interval(hours => greatest(p_horas,1));

  IF coalesce(v_n,0) = 1 AND v_um = v_cod THEN
    RETURN 'unico_card';
  END IF;

  RETURN 'nao';
END;
$function$;
