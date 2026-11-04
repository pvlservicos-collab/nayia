CREATE OR REPLACE FUNCTION public.campanha_msg_seguinte(p_lista text, p_codigos integer[])
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_n    int := cardinality(p_codigos);
  v_txt  text;
  v_v30  int;
  v_verbo text;
BEGIN
  IF p_lista NOT IN ('donos_parados', 'feedback_disponiveis') THEN
    RETURN NULL;
  END IF;
  v_txt := campanha_metricas_grupo(p_codigos);
  SELECT sum((campanha_metricas(c)->>'visitas_30d')::int) INTO v_v30 FROM unnest(p_codigos) c;
  SELECT CASE WHEN bool_or(coalesce(valor_aluguel, 0) > 0) AND bool_or(coalesce(valor_venda, 0) > 0) THEN 'alugar ou vender'
              WHEN bool_or(coalesce(valor_aluguel, 0) > 0) THEN 'alugar' ELSE 'vender' END
    INTO v_verbo FROM imoveis WHERE codigo = ANY (p_codigos);
  IF p_lista = 'donos_parados' THEN
    RETURN 'Que bom! ' || v_txt || ' Nos últimos 30 dias ninguém pediu visita. Para ' || v_verbo
           || ' mais rápido, toparia ajustar o valor?'
           || CASE WHEN v_n = 1 THEN ' Hoje ele está em ' || campanha_valor_texto(p_codigos[1]) || '.' ELSE '' END
           || ' Se topar, me diz o novo valor que eu passo para a equipe atualizar o anúncio.';
  END IF;
  RETURN 'Ótimo, obrigada por confirmar! Para você acompanhar: ' || lower(left(v_txt, 1)) || substr(v_txt, 2)
         || CASE WHEN coalesce(v_v30, 0) > 0
                 THEN ' Nos últimos 30 dias ' || CASE WHEN v_n = 1 THEN 'ele teve ' ELSE 'eles tiveram ' END || v_v30
                      || CASE WHEN v_v30 = 1 THEN ' visita.' ELSE ' visitas.' END
                 ELSE ' Nos últimos 30 dias ninguém pediu visita.' END
         || ' Se quiser ' || v_verbo || ' mais rápido, um ajuste no valor costuma ajudar bastante. Se topar, me diz o novo valor'
         || ' que eu passo para a equipe.';
END;
$function$;
