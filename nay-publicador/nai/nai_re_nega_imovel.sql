CREATE OR REPLACE FUNCTION public.nai_re_nega_imovel()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT '(n[ãa]o\s+(encontrei|achei|localizei|tenho\s+esse)|qual\s+[ée]\s+o\s+\d{3,5})';
$function$
;
