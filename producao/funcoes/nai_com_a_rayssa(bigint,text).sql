CREATE OR REPLACE FUNCTION public.nai_com_a_rayssa(p_contato bigint, p_papel text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
-- NULL = a Nay atende. Senão, o motivo de a conversa ser da Rayssa.
DECLARE v_ids bigint[];
BEGIN
  IF p_contato IS NULL OR nai_cfg('visita_com_a_rayssa', 'sim') <> 'sim' OR nai_e_da_equipe_contato(p_contato) THEN
    RETURN NULL;
  END IF;
  v_ids := coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]);
  IF EXISTS (SELECT 1 FROM nai_fechamento f WHERE f.contato_id = ANY (v_ids) AND f.concluido_em IS NULL) THEN
    RETURN 'fechamento_com_a_rayssa';
  END IF;
  IF EXISTS (SELECT 1 FROM nai_visita v WHERE v.corretor_id = ANY (v_ids) AND nai_visita_com_a_rayssa(v.estado, v.quando)) THEN
    RETURN 'visita_com_a_rayssa';
  END IF;
  IF p_papel = 'proprietario' OR nai_e_proprietario_contato(p_contato) THEN
    RETURN 'proprietario_com_a_rayssa';
  END IF;
  RETURN NULL;
END $function$;
