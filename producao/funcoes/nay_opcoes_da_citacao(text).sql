CREATE OR REPLACE FUNCTION public.nay_opcoes_da_citacao(p_message_id text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_cods text[] := nay_codigos_da_saida(p_message_id);
  v_lista text;
BEGIN
  IF coalesce(array_length(v_cods,1),0) < 2 THEN RETURN NULL; END IF;

  SELECT string_agg('• ' || i.codigo || ' — '
                    || coalesce(NULLIF(i.condominio_nome,''), NULLIF(i.tipo,''), 'imóvel')
                    || coalesce(' — ' || i.quartos || ' quartos', ''),
                    chr(10) ORDER BY i.codigo)
    INTO v_lista
    FROM imoveis i
   WHERE i.codigo::text = ANY (v_cods);

  RETURN v_lista;
END;
$function$;
