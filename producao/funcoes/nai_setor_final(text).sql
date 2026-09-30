CREATE OR REPLACE FUNCTION public.nai_setor_final(p_nome text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    (SELECT e.setor FROM nai_setor_excecao e WHERE e.funcao = p_nome),
    nai_setor_de_funcao(p_nome));
$function$;
