CREATE OR REPLACE FUNCTION public.nai_uma_pergunta_da_sequencia(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE t text := coalesce(p_texto, ''); p_bai int; p_pre int; p_mob int;
BEGIN
  IF t !~ '\?' OR t ~* 'c[óo]digo:' OR length(t) >= 300 THEN RETURN NULL; END IF;
  p_bai := coalesce(nullif(strpos(lower(t), 'bairro'), 0), 0);
  p_pre := coalesce(nullif(strpos(lower(t), 'faixa de pre'), 0), 0);
  p_mob := coalesce(nullif(strpos(lower(t), 'mobiliad'), 0), 0);
  IF (CASE WHEN p_bai > 0 THEN 1 ELSE 0 END) + (CASE WHEN p_pre > 0 THEN 1 ELSE 0 END)
   + (CASE WHEN p_mob > 0 THEN 1 ELSE 0 END) < 2 THEN RETURN NULL; END IF;
  RETURN CASE
    WHEN p_bai > 0 AND (p_pre = 0 OR p_bai < p_pre) AND (p_mob = 0 OR p_bai < p_mob)
      THEN 'Eu também tenho outras opções de locação, você está procurando imóveis em qual bairro?'
    WHEN p_pre > 0 AND (p_mob = 0 OR p_pre < p_mob)
      THEN 'E qual a faixa de preço que seus clientes estão buscando?'
    ELSE 'E eles têm preferência por semimobiliado ou mobiliado?' END;
END;
$function$
;
