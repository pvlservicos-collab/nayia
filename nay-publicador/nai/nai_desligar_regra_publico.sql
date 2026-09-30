CREATE OR REPLACE FUNCTION public.nai_desligar_regra_publico()
 RETURNS text
 LANGUAGE sql
AS $function$
  UPDATE nai_config SET valor = 'nao' WHERE chave = 'regra_publico';
  SELECT 'Regra desligada. O carimbo de quando ligou fica guardado.'::text;
$function$
;
