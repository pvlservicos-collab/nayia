CREATE OR REPLACE FUNCTION public.nay_registrar_mensagem_grupo(p_message_id text, p_grupo_id text, p_grupo_nome text, p_remetente text, p_texto text, p_instancia text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_cods text[]; v_cod int;
BEGIN
  -- Guarda CARD DE IMOVEL, nao a conversa do grupo. Duas formas:
  -- com "Codigo: NNNN" (o card que a gente posta) e sem codigo nenhum, escrito
  -- a mao (o Tel postou assim no Anunciar Easy em 13/09: "📍Residencial IBIZA
  -- FLEX / 2 quartos sendo 1 suite / 3.900"). No segundo caso o ID fica
  -- guardado com `codigo` nulo -- e o que permite amarrar depois.
  IF nullif(btrim(coalesce(p_message_id, '')), '') IS NULL
     OR NOT (coalesce(p_texto, '') ~* 'c[óo]digo:\s*\d{3,5}'
             OR (coalesce(p_texto, '') ~ '(📍|•|▪)'
                 AND coalesce(p_texto, '') ~* '(r\$|alug|quarto|su[íi]te|mobiliad|m2|m²)')) THEN
    RETURN NULL;
  END IF;
  SELECT array_agg(DISTINCT m[1]) INTO v_cods
    FROM regexp_matches(p_texto, 'C[óo]digo:\s*(\d{3,5})', 'gi') AS m;
  -- Dois codigos no mesmo texto: nao escolhe (a Nay pergunta, com a lista).
  IF coalesce(array_length(v_cods, 1), 0) = 1 THEN
    SELECT i.codigo INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
  END IF;
  INSERT INTO grupo_mensagens (message_id, grupo_id, grupo_nome, remetente, texto, codigo, instancia)
  VALUES (btrim(p_message_id), p_grupo_id, p_grupo_nome, p_remetente, left(p_texto, 2000), v_cod, p_instancia)
  ON CONFLICT (message_id) DO NOTHING;
  RETURN v_cod;
END;
$function$;
