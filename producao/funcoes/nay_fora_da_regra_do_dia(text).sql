CREATE OR REPLACE FUNCTION public.nay_fora_da_regra_do_dia(p_chave text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p_chave IS NULL
      OR p_chave = nai_chave(nai_cfg('tel_telefone'))
      OR p_chave = ANY (nai_chaves_teste())
      OR EXISTS (SELECT 1 FROM nai_contato c
                  WHERE c.chave = p_chave AND nai_e_da_equipe_contato(c.id))
      OR EXISTS (SELECT 1 FROM nay_e_da_equipe(p_chave));
$function$;
