CREATE OR REPLACE FUNCTION public.blog_categoria_nome(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p WHEN 'sobre-nos' THEN 'Sobre nós' WHEN 'clientes' THEN 'Clientes' WHEN 'corretores' THEN 'Corretores'
                WHEN 'locacao' THEN 'Imóveis de locação' WHEN 'venda' THEN 'Imóveis de venda' ELSE coalesce(p, '') END
$function$;
