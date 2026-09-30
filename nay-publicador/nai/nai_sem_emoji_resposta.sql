CREATE OR REPLACE FUNCTION public.nai_sem_emoji_resposta(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(translate(
           regexp_replace(regexp_replace(regexp_replace(
             translate(coalesce(p, ''), '🏢🏠📍🛏🚗💰📐🔑🔐📅🕐📌',
                       chr(1) || chr(2) || chr(3) || chr(4) || chr(5) || chr(6) || chr(7) || chr(14) || chr(15)
                       || chr(16) || chr(17) || chr(18)),
             '[🀀-🫿☀-➿️‍]', '', 'g'),
             '[ \t]{2,}', ' ', 'g'),
             '[ \t]+$', '', 'gn'),
           chr(1) || chr(2) || chr(3) || chr(4) || chr(5) || chr(6) || chr(7) || chr(14) || chr(15)
           || chr(16) || chr(17) || chr(18), '🏢🏠📍🛏🚗💰📐🔑🔐📅🕐📌'));
$function$
;
