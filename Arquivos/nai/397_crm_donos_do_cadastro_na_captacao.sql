-- 397: quem é DONO DE IMÓVEL no cadastro, para a aba Proprietários da Captação no CRM
--
-- Pedro, 16/10/2026: "no CRM número captação pôr a aba proprietário também". A aba Proprietários da Captação só
-- juntava os donos da campanha e o cliente da OLX que a equipe pôs ali; o dono do cadastro que escreve no 8595 fora da
-- campanha (57 de 461 contatos em 16/10, o Cristian do 9045 entre eles) ficava só em Todos. Na Parceria, Proprietários
-- é "quem a Nay sabe que é dono de imóvel": agora vale igual na Captação.
-- O CRM manda os 8 últimos dígitos dos contatos da linha e recebe os que são donos (proprietarios.telefone).
BEGIN;
CREATE OR REPLACE FUNCTION public.crm_donos_do_cadastro(p_fins text[])
 RETURNS TABLE(fim8 text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT DISTINCT right(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g'), 8)
    FROM proprietarios p
   WHERE right(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g'), 8) = ANY (coalesce(p_fins, '{}'))
$function$;
REVOKE ALL ON FUNCTION public.crm_donos_do_cadastro(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_donos_do_cadastro(text[]) TO nay_disparo;
COMMIT;
