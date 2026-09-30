CREATE OR REPLACE FUNCTION public.nai_e_proprietario_contato(p_contato bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
-- A MESMA REGRA DA ABA PROPRIETÁRIOS DO CRM (crm_parceria_marcas, 173): o cadastro
-- do site, o do admin antigo, quem a captação procurou ou o dono de uma visita;
-- corretor parceiro não é proprietário, e a equipe não é nem um nem outro.
DECLARE
  v_ids    bigint[] := coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]);
  v_chaves text[];
BEGIN
  IF p_contato IS NULL OR nai_e_da_equipe_contato(p_contato) THEN RETURN false; END IF;
  SELECT array_agg(DISTINCT c.chave) INTO v_chaves FROM nai_contato c WHERE c.id = ANY (v_ids) AND c.chave IS NOT NULL;
  IF EXISTS (SELECT 1 FROM corretores c WHERE nai_chave(c.telefone) = ANY (v_chaves)) THEN RETURN false; END IF;
  RETURN EXISTS (SELECT 1 FROM nai_visita v WHERE v.proprietario_id = ANY (v_ids))
      OR EXISTS (SELECT 1 FROM proprietarios p WHERE coalesce(p.telefone, '') <> '' AND nai_chave(p.telefone) = ANY (v_chaves))
      OR EXISTS (SELECT 1 FROM proprietarios_admin a WHERE coalesce(a.telefone, '') <> '' AND nai_chave(a.telefone) = ANY (v_chaves))
      OR EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = ANY (v_chaves));
END $function$;
