CREATE OR REPLACE FUNCTION public.captacao_ja_perguntou_outros(p_lead bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM captacao_mensagens m
     WHERE m.lead_id = p_lead AND m.direcao = 'enviada'
       AND lower(unaccent(coalesce(m.texto, ''))) ~ '\m(outro imovel|outros imoveis|algum outro)\M');
$function$;
