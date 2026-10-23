CREATE OR REPLACE FUNCTION public.captacao_nay_perfis()
 RETURNS TABLE(nome text, ativo boolean, descricao text, listas text, prompt_papel text, prompt_versao_salva integer, prompt_versao_viva integer, roteiro text, leads bigint, salvo_em timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p.nome, p.nome = (SELECT valor FROM captacao_config WHERE chave = 'nay_perfil_ativo'), p.descricao, p.listas,
         p.prompt_papel, p.prompt_versao, (SELECT n.versao FROM nai_prompt n WHERE n.papel = p.prompt_papel), p.roteiro,
         (SELECT count(*) FROM captacao_leads l WHERE coalesce(l.perfil_nay, 'proprietarios') = p.nome), p.salvo_em
    FROM captacao_nay_perfil p ORDER BY p.nome;
$function$;
