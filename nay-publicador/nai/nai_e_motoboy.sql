CREATE OR REPLACE FUNCTION public.nai_e_motoboy(p_chave text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM equipe WHERE papel = 'acompanhante' AND ativo AND nai_chave(telefone) = p_chave);
$function$
;
