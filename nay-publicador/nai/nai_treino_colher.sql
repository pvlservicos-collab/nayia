CREATE OR REPLACE FUNCTION public.nai_treino_colher(p_caso bigint, p_turno bigint)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_texto text; v_ferr text[]; v_exec text;
BEGIN
  -- `x.texto` E NAO `resposta->>'texto_final'`. Os dois existem e sao
  -- diferentes: o segundo e o primeiro com a ETIQUETA do modo teste colada
  -- na frente ("TESTE - iria para o CORRETOR Fulano..."). Essa etiqueta e
  -- do transporte, nao dela -- e no ciclo 1 ela apareceu em todas as
  -- respostas, empurrando o texto real para fora da previa da lista.
  -- Para julgar o que ELA escreveu, o certo e o texto cru.
  SELECT string_agg(x.texto, E'\n---\n' ORDER BY x.ordem, x.id)
    INTO v_texto
    FROM nai_saida x
   WHERE x.turno_id = p_turno AND x.tipo = 'texto';

  SELECT t.ferramentas INTO v_ferr FROM nai_turno t WHERE t.id = p_turno;
  SELECT e.exec_id INTO v_exec FROM nai_evento e
   WHERE e.turno_id = p_turno AND e.exec_id IS NOT NULL ORDER BY e.id LIMIT 1;

  UPDATE nai_treino_caso
     SET turno_simulado      = p_turno,
         ela_respondeu_agora = v_texto,
         ferramentas_agora   = coalesce(v_ferr, '{}'),
         exec_id             = v_exec,
         estado              = 'rodado',
         erro                = NULL,
         rodado_em           = now()
   WHERE id = p_caso;

  RETURN v_texto;
END;
$function$
;
