CREATE OR REPLACE FUNCTION public.nai_re_promessa()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT '(assim que (eu )?(tiver|souber|receber|ele responder|me responderem)|vou (verificar|confirmar|checar|consultar|perguntar)|(j[áa]|logo) te (retorno|aviso)|te (retorno|aviso) (em seguida|assim que|logo)|est(á|a|ou) verificando|n[ãa]o (tenho|sei|achei|encontrei) (essa|esta|a|nenhuma) informa)';
$function$
;
