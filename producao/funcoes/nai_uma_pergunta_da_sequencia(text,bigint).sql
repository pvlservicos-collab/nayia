CREATE OR REPLACE FUNCTION public.nai_uma_pergunta_da_sequencia(p_texto text, p_contato bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t text := coalesce(p_texto, ''); p_bai int; p_pre int; p_mob int;
  pf nai_perfil_cliente;
  sabe_bairro boolean := false; sabe_valor boolean := false; sabe_mob boolean := false;
BEGIN
  IF t !~ '\?' OR t ~* 'c[óo]digo:' OR length(t) >= 300 THEN RETURN NULL; END IF;
  p_bai := coalesce(nullif(strpos(lower(t), 'bairro'), 0), 0);
  p_pre := coalesce(nullif(strpos(lower(t), 'faixa de pre'), 0), 0);
  p_mob := coalesce(nullif(strpos(lower(t), 'mobiliad'), 0), 0);
  IF (CASE WHEN p_bai > 0 THEN 1 ELSE 0 END) + (CASE WHEN p_pre > 0 THEN 1 ELSE 0 END)
   + (CASE WHEN p_mob > 0 THEN 1 ELSE 0 END) < 2 THEN RETURN NULL; END IF;

  -- 225: O QUE ELE JÁ DISSE NÃO SE PERGUNTA (Pedro, 30/09: a Maria Soraia disse
  -- "Mobiliado R$4,000 ... Adrianópolis" e ouviu "prefere semimobiliado ou
  -- mobiliado?"). O perfil do cliente (223) guarda o que a busca já recebeu.
  IF p_contato IS NOT NULL THEN
    SELECT * INTO pf FROM nai_perfil_ativo(p_contato);
    sabe_bairro := nullif(btrim(coalesce(pf.bairros, '')), '') IS NOT NULL;
    sabe_valor  := pf.teto IS NOT NULL;
    sabe_mob    := nullif(btrim(coalesce(pf.mobilia, '')), '') IS NOT NULL;
  END IF;

  RETURN CASE
    WHEN p_bai > 0 AND NOT sabe_bairro
      THEN 'Eu também tenho outras opções de locação, você está procurando imóveis em qual bairro?'
    WHEN p_pre > 0 AND NOT sabe_valor
      THEN 'E qual a faixa de preço que seus clientes estão buscando?'
    WHEN p_mob > 0 AND NOT sabe_mob
      THEN 'E eles têm preferência por semimobiliado ou mobiliado?'
    ELSE NULL END;
END;
$function$;
