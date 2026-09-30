CREATE OR REPLACE FUNCTION public.nay_imovel_em_foco(p_telefone text, p_horas integer DEFAULT NULL::integer)
 RETURNS TABLE(codigo text, descricao text, opcoes text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_cods text[] := nay_codigos_da_conversa(p_telefone, p_horas);
  v_n    int := coalesce(array_length(v_cods,1),0);
BEGIN
  IF v_n = 0 THEN
    RETURN QUERY SELECT NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;

  IF v_n = 1 THEN
    RETURN QUERY
    SELECT i.codigo::text,
           (coalesce(NULLIF(i.condominio_nome,''), NULLIF(i.tipo,''), 'o imóvel')
            || coalesce(' em ' || NULLIF(i.bairro,''), '')
            || ', código ' || i.codigo)::text,
           NULL::text
      FROM imoveis i WHERE i.codigo::text = v_cods[1];
    RETURN;
  END IF;

  -- Mais de um imóvel nesta conversa: ela pergunta, com as opções. Isto
  -- é o oposto de supor -- e é a mesma escolha do `nay_qual_imovel`.
  RETURN QUERY
  SELECT NULL::text, NULL::text,
         string_agg('• ' || i.codigo || ' — '
                    || coalesce(NULLIF(i.condominio_nome,''), NULLIF(i.tipo,''), 'imóvel')
                    || coalesce(' em ' || NULLIF(i.bairro,''), ''),
                    chr(10) ORDER BY i.codigo)::text
    FROM imoveis i WHERE i.codigo::text = ANY (v_cods);
END;
$function$;
