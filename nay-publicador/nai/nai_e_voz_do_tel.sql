CREATE OR REPLACE FUNCTION public.nai_e_voz_do_tel(p_chave text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p_chave = nai_chave(nai_cfg('tel_telefone'))
      OR nai_pode_comandar(p_chave);
$function$
;
