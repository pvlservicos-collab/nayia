CREATE OR REPLACE FUNCTION public.campanha_metricas_grupo(p_codigos integer[])
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_n    int := cardinality(p_codigos);
  v_ms   jsonb[];
  v_meses int;
  v_site boolean;
  v_cnm  boolean;
  v_extra text[];
  v_txt  text;
  m jsonb;
  p text[];
BEGIN
  IF v_n = 1 THEN
    RETURN campanha_metricas_texto(campanha_metricas(p_codigos[1]));
  END IF;
  SELECT array_agg(campanha_metricas(c) ORDER BY o) INTO v_ms FROM unnest(p_codigos) WITH ORDINALITY u(c, o);
  SELECT count(DISTINCT campanha_mes((x->>'desde')::date)), bool_and((x->>'no_site')::boolean), bool_and((x->>'chaves_na_mao')::boolean)
    INTO v_meses, v_site, v_cnm FROM unnest(v_ms) x;
  IF v_meses <> 1 THEN
    SELECT string_agg(campanha_metricas_texto(x), ' ' ORDER BY o) INTO v_txt FROM unnest(v_ms[1:3]) WITH ORDINALITY u(x, o);
    RETURN v_txt || CASE WHEN v_n = 4 THEN ' O outro segue anunciado do mesmo jeito.'
                         WHEN v_n > 4 THEN ' Os outros ' || (v_n - 3) || ' seguem anunciados do mesmo jeito.' ELSE '' END;
  END IF;
  v_txt := 'Os ' || coalesce((ARRAY['', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove', 'dez'])[v_n], v_n::text)
           || CASE WHEN v_site THEN ' estão no nosso site desde ' ELSE ' estão cadastrados conosco desde ' END
           || campanha_mes((v_ms[1]->>'desde')::date) || CASE WHEN v_cnm THEN ' e no portal Chaves na Mão' ELSE '' END;
  FOREACH m IN ARRAY v_ms LOOP
    p := array_remove(ARRAY[
           CASE WHEN NOT v_cnm AND (m->>'chaves_na_mao')::boolean THEN 'está no portal Chaves na Mão' END,
           CASE WHEN (m->>'posts')::int > 0
                THEN 'já foi divulgado ' || (m->>'posts') || CASE WHEN (m->>'posts')::int = 1 THEN ' vez' ELSE ' vezes' END
                     || ' em grupos de corretores' END,
           CASE WHEN (m->>'clientes')::int > 0
                THEN 'foi apresentado a ' || (m->>'clientes') || CASE WHEN (m->>'clientes')::int = 1 THEN ' cliente' ELSE ' clientes' END END], NULL);
    IF cardinality(p) > 0 THEN
      v_extra := v_extra || ('o ' || (m->>'codigo') || ' ' || campanha_lista_texto(p));
    END IF;
  END LOOP;
  RETURN v_txt || CASE WHEN cardinality(v_extra) > 0 THEN '; ' || array_to_string(v_extra, '; ') ELSE '' END || '.';
END;
$function$;
