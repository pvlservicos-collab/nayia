CREATE OR REPLACE FUNCTION public.captacao_e_do_python(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce((
    SELECT btrim(c.valor) = 'todos'
        OR nay_fone_chave(p_telefone) IN (SELECT nay_fone_chave(btrim(x)) FROM regexp_split_to_table(c.valor, '[,;\s]+') x WHERE btrim(x) <> '')
      FROM captacao_config c WHERE c.chave = 'python_telefones'), false);
$function$;
