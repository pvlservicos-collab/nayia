CREATE OR REPLACE FUNCTION public.nai_e_link_de_produto(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- wa.me/p/... e o produto do catalogo do WhatsApp Business. O /c/ e o
  -- catalogo inteiro. Os dois querem dizer "estou falando DESTE imovel".
  SELECT lower(coalesce(p_texto, '')) ~ '(wa\.me/p/|api\.whatsapp\.com/product|/catalog/)';
$function$
;
