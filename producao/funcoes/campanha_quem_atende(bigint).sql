CREATE OR REPLACE FUNCTION public.campanha_quem_atende(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  r privado.campanha_contato;
  v_contato bigint;
BEGIN
  SELECT * INTO r FROM privado.campanha_contato WHERE id = p_id;
  IF NOT FOUND THEN RETURN 'sem_contato'; END IF;
  -- a Nay Leads está falando com ele por um cliente (dúvida, visita): é dela
  IF EXISTS (SELECT 1 FROM nay_leads_com_dono d WHERE d.chave = r.chave AND d.ate > now()
                AND coalesce(d.motivo, '') NOT LIKE 'campanha%') THEN
    RETURN 'nay_leads_com_o_dono';
  END IF;
  IF EXISTS (SELECT 1 FROM olx_visita_consulta c WHERE c.estado = 'esperando' AND right(c.telefone, 8) = r.tel8) THEN
    RETURN 'visita_da_nay_leads';
  END IF;
  IF r.linha = 'parceria' THEN
    SELECT id INTO v_contato FROM nai_contato WHERE chave = r.chave;
    IF v_contato IS NULL THEN RETURN NULL; END IF;
    IF nai_tel_com_a_conversa(v_contato) THEN RETURN 'equipe'; END IF;
    IF captacao_olx_da_parceria(r.telefone, v_contato) IS NOT NULL THEN RETURN 'nay_captacao_olx'; END IF;
    IF cadastro_whats_da_parceria(r.telefone, v_contato) IS NOT NULL THEN RETURN 'nay_cadastro'; END IF;
    IF EXISTS (SELECT 1 FROM nai_visita x WHERE x.proprietario_id = v_contato AND nai_visita_aberta(x.estado)) THEN
      RETURN 'visita_da_parceria';
    END IF;
    -- a Nay da Parceria (nay-core) atende CORRETOR; dono de imóvel (nay_proprietario_bloqueio, 463) ela não atende
    IF NOT EXISTS (SELECT 1 FROM nay_proprietario_bloqueio b WHERE b.chave = r.chave) THEN
      RETURN 'nay_parceria';
    END IF;
    RETURN NULL;
  END IF;
  IF EXISTS (SELECT 1 FROM olx_lead_whatsapp o WHERE right(o.telefone, 8) = r.tel8) THEN RETURN 'nay_leads'; END IF;
  IF captacao_e_do_python(r.telefone) THEN RETURN 'nay_captacao'; END IF;
  IF r.linha = 'captacao' AND busca_corretor_e(r.telefone) THEN RETURN 'nay_corretores'; END IF;
  RETURN NULL;
END;
$function$;
