CREATE OR REPLACE FUNCTION public.nay_imovel_da_citacao(p_message_id text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_id   text := NULLIF(btrim(coalesce(p_message_id,'')), '');
  v_cod  text;
  v_cods text[];
BEGIN
  IF v_id IS NULL THEN RETURN NULL; END IF;

  -- 1. o que o publicador mandou (grupo ou corretor)
  SELECT e.codigo INTO v_cod FROM envios e
   WHERE e.message_id = v_id ORDER BY e.enviado_em DESC LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 2. o que a NAI mandou no privado: card, foto ou colagem
  SELECT s.codigo::text INTO v_cod FROM nai_saida s
   WHERE s.message_id = v_id AND s.codigo IS NOT NULL ORDER BY s.id DESC LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 2b. card em texto da NAI: o código está dentro da mensagem
  SELECT array_agg(DISTINCT m[1]) INTO v_cods
    FROM nai_saida s
    CROSS JOIN LATERAL regexp_matches(coalesce(s.texto, ''), 'C[óo]digo:\s*(\d{3,5})', 'gi') AS m
   WHERE s.message_id = v_id;
  IF coalesce(array_length(v_cods, 1), 0) = 1 THEN
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;
  END IF;

  -- 3. A MENSAGEM DELE (14/09): ele marcou o card que ele mesmo colou, ou uma
  --    mensagem dele que citava o código. Dois códigos no mesmo texto não
  --    escolhem nada -- ela pergunta, com a lista.
  SELECT array_agg(DISTINCT x) INTO v_cods
    FROM mensagens m
    CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto, '') || ' ' || coalesce(m.citado, '')), '{}'::text[])) x
   WHERE m.message_id = v_id AND x ~ '^[0-9]{3,5}$';
  IF coalesce(array_length(v_cods, 1), 0) = 1 THEN
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;
  END IF;

  -- 4. card visto em grupo (inclusive o que o Tel posta pelo celular dele)
  SELECT g.codigo::text INTO v_cod FROM grupo_mensagens g
   WHERE g.message_id = v_id AND g.codigo IS NOT NULL LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 5. a saída da Nay antiga
  v_cods := nay_codigos_da_saida(v_id);
  IF coalesce(array_length(v_cods,1),0) = 1 THEN
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    RETURN v_cod;
  END IF;

  RETURN NULL;
END;
$function$;
