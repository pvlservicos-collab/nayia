CREATE OR REPLACE FUNCTION public.nay_titulo_da_categoria(p_categoria text, p_negocio text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_categoria
    WHEN 'apartamento'            THEN 'APARTAMENTOS'
    WHEN 'apartamento_via_publica' THEN 'APARTAMENTOS EM VIA PÚBLICA'
    WHEN 'casa_condominio'        THEN 'CASAS EM CONDOMÍNIO'
    WHEN 'casa_via_publica'       THEN 'CASAS EM VIA PÚBLICA'
    WHEN 'sala'                   THEN 'SALAS COMERCIAIS'
    WHEN 'lote'                   THEN 'LOTES'
    ELSE upper(coalesce(p_categoria,'IMÓVEIS'))
  END || CASE WHEN p_negocio = 'venda' THEN ' PARA VENDA'
              ELSE ' PARA LOCAÇÃO' END;
$function$;
