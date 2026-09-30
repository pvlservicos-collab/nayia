CREATE OR REPLACE FUNCTION public.nai_e_assunto_de_locacao(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE COST 300
AS $function$
  SELECT s ~ '\m(foto|fotos|card|codigo|valor|aluguel|venda|visita|visitar|agendar|dispon|quartos?|suite|mobiliad|condominio|bairro|apartamento|casa|imovel|imoveis)\M'
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;
