CREATE OR REPLACE FUNCTION public.nai_treino_semear_memoria(p_caso bigint, p_sessao text, p_quantos integer DEFAULT 12)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_contato bigint;
  v_ate     timestamptz;
  v_n       int := 0;
BEGIN
  SELECT contato_origem, quando_original INTO v_contato, v_ate
    FROM nai_treino_caso WHERE id = p_caso;
  IF v_contato IS NULL THEN
    RAISE EXCEPTION 'caso % nao existe', p_caso;
  END IF;

  DELETE FROM nai_memoria WHERE session_id = p_sessao;

  -- As trocas ANTERIORES ao turno do caso, da mais antiga para a mais nova.
  -- O formato e o do LangChain: {type: human|ai, data:{content}}.
  -- As ULTIMAS p_quantos falas, nao as primeiras: a janela do no de memoria
  -- do n8n e 40, e o que importa e o que estava perto do turno.
  --
  -- Pega o fim pela ORDEM INVERSA com LIMIT, e so depois reordena para a
  -- ordem da conversa. A primeira versao disto calculava um OFFSET a partir
  -- de `numero de turnos * 2`, e estava errado: nem todo turno gera as duas
  -- falas -- turno sem texto nao gera a humana, turno sem resposta nao gera
  -- a da IA. O OFFSET cortava no lugar errado e a memoria comecava no meio
  -- de uma troca.
  INSERT INTO nai_memoria (session_id, message)
  SELECT p_sessao, u.message FROM (
    SELECT m.q, m.lado, m.message
      FROM (
        SELECT t.criado_em AS q, 0 AS lado,
               jsonb_build_object('type','human',
                 'data', jsonb_build_object('content', t.texto,
                                            'additional_kwargs', '{}'::jsonb,
                                            'response_metadata', '{}'::jsonb)) AS message
          FROM nai_turno t
         WHERE t.contato_id = v_contato AND t.criado_em < v_ate AND t.texto IS NOT NULL
        UNION ALL
        SELECT t.criado_em AS q, 1 AS lado,
               jsonb_build_object('type','ai',
                 'data', jsonb_build_object('content',
                           (SELECT string_agg(x.texto, E'\n' ORDER BY x.ordem, x.id)
                              FROM nai_saida x
                             WHERE x.turno_id = t.id AND x.tipo='texto'),
                                            'additional_kwargs', '{}'::jsonb,
                                            'response_metadata', '{}'::jsonb,
                                            'tool_calls', '[]'::jsonb,
                                            'invalid_tool_calls', '[]'::jsonb)) AS message
          FROM nai_turno t
         WHERE t.contato_id = v_contato AND t.criado_em < v_ate
           AND EXISTS (SELECT 1 FROM nai_saida x WHERE x.turno_id=t.id AND x.tipo='texto')
      ) m
     WHERE m.message->'data'->>'content' IS NOT NULL
     ORDER BY m.q DESC, m.lado DESC
     LIMIT p_quantos
  ) u
  ORDER BY u.q, u.lado;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;
