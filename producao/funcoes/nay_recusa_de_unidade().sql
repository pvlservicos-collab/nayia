CREATE OR REPLACE FUNCTION public.nay_recusa_de_unidade()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT 'RECUSE, e NAO escale ao Tel. Diga ao corretor, com as suas palavras '
      || 'e no seu tom, que o numero do apartamento, o bloco, a torre e o andar '
      || 'a gente so passa na hora da visita agendada -- e politica da Imob Easy '
      || 'para todos os imoveis, nao e nada contra ele. Ofereca agendar a visita, '
      || 'que e quando ele ve tudo. NAO prometa verificar, NAO diga que vai '
      || 'perguntar ao Tel, NAO diga que retorna depois: nao existe retorno, a '
      || 'resposta e essa. Se ele insistir, repita uma vez e siga ajudando no '
      || 'resto -- valor, area, quartos, fotos, tudo isso voce passa normalmente.';
$function$;
