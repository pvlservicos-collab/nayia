CREATE OR REPLACE FUNCTION public.nai_re_promete_foto()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT '((segue|seguem|vou te (mandar|enviar|passar)|te (mando|envio|passo)|mandando|enviando|j[áa] (te )?mando)[^.?!\n]{0,25}(as |umas )?(fotos?|imagens?))';
$function$;
