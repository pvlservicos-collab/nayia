CREATE OR REPLACE FUNCTION public.captacao_nay_perfil_do_lead(p_telefone text)
 RETURNS TABLE(nome text, prompt_papel text, roteiro text, prompt text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p.nome, p.prompt_papel, p.roteiro, nai_prompt_de(p.prompt_papel)
    FROM captacao_nay_perfil p
   WHERE p.nome = coalesce((SELECT l.perfil_nay FROM captacao_leads l
                             WHERE l.telefone_chave = nay_fone_chave(p_telefone) ORDER BY l.id DESC LIMIT 1),
                           'proprietarios');
$function$;
