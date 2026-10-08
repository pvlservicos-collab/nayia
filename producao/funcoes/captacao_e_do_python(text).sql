CREATE OR REPLACE FUNCTION public.captacao_e_do_python(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce((
    SELECT btrim(c.valor) = 'todos'
        OR nay_fone_chave(p_telefone) IN (SELECT nay_fone_chave(btrim(x)) FROM regexp_split_to_table(c.valor, '[,;\s]+') x WHERE btrim(x) <> '')
      FROM captacao_config c WHERE c.chave = 'python_telefones'), false)
      OR EXISTS (SELECT 1 FROM captacao_motor mt JOIN captacao_leads l ON l.id = mt.lead_id
                  WHERE mt.motor = 'python' AND l.telefone_chave = nay_fone_chave(p_telefone));
$function$;
