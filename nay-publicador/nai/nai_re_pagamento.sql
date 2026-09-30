CREATE OR REPLACE FUNCTION public.nai_re_pagamento()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$ SELECT '(financ|[àa]\s+vista|avista|fgts|permuta)'::text $function$
;
