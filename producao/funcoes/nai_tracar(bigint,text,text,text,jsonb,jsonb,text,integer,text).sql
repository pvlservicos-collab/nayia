CREATE OR REPLACE FUNCTION public.nai_tracar(p_turno bigint, p_setor text, p_etapa text, p_resultado text DEFAULT 'ok'::text, p_entrada jsonb DEFAULT NULL::jsonb, p_saida jsonb DEFAULT NULL::jsonb, p_detalhe text DEFAULT NULL::text, p_ms integer DEFAULT NULL::integer, p_exec text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_nivel   text;
  v_res     text := coalesce(nullif(btrim(p_resultado), ''), 'ok');
  v_seq     int;
  v_payload boolean;
  v_id      bigint;
BEGIN
  v_nivel := nai_cfg('trace_nivel', 'completo');
  IF v_nivel = 'desligado' THEN RETURN NULL; END IF;
  -- Modo barato: só o que deu problema. Serve para deixar ligado para sempre
  -- sem a tabela crescer.
  IF v_nivel = 'problema' AND v_res = 'ok' THEN RETURN NULL; END IF;
  -- Resultado fora do vocabulário não recusa o evento: vira 'erro' e o
  -- detalhe guarda o que veio. Trace que recusa dado é trace que mente.
  IF v_res NOT IN ('ok','mudou','cortou','parou','erro') THEN
    p_detalhe := coalesce(p_detalhe || ' | ', '') || 'resultado recebido: ' || v_res;
    v_res := 'erro';
  END IF;

  v_payload := nai_cfg('trace_payload', 'sim') = 'sim';

  -- A sequência é por turno. Duas inserções no MESMO turno em paralelo podem
  -- repetir o número -- na prática um turno é serial, e o `id` desempata na
  -- ordenação, então não vale travar linha por isso.
  IF p_turno IS NULL THEN
    v_seq := 0;
  ELSE
    SELECT coalesce(max(e.seq), 0) + 1 INTO v_seq FROM nai_evento e WHERE e.turno_id = p_turno;
  END IF;

  INSERT INTO nai_evento (turno_id, exec_id, seq, setor, etapa, resultado, ms,
                          entrada, saida, detalhe)
  VALUES (p_turno,
          nullif(btrim(coalesce(p_exec, '')), ''),
          v_seq,
          left(coalesce(nullif(btrim(p_setor), ''), 'entrada'), 40),
          left(coalesce(nullif(btrim(p_etapa), ''), '(sem nome)'), 120),
          v_res,
          p_ms,
          CASE WHEN v_payload THEN nai_mascarar(p_entrada) END,
          CASE WHEN v_payload THEN nai_mascarar(p_saida) END,
          left(p_detalhe, 2000))
  RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN others THEN
  -- O atendimento continua. Sempre.
  RETURN NULL;
END;
$function$;
