CREATE OR REPLACE FUNCTION public.nai_com_a_rayssa(p_contato bigint, p_papel text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
-- NULL = a Nay atende. Senão, o motivo de a conversa ser da Rayssa (197, 201).
DECLARE
  v_ids   bigint[];
  v_etapa text;
  v_em    timestamptz;
BEGIN
  IF p_contato IS NULL OR nai_cfg('visita_com_a_rayssa', 'sim') <> 'sim' OR nai_e_da_equipe_contato(p_contato) THEN
    RETURN NULL;
  END IF;
  v_ids := coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]);
  SELECT m.etapa, m.definido_em INTO v_etapa, v_em
    FROM nai_etapa_manual m
   WHERE m.contato_id = ANY (v_ids) AND (m.valido_ate IS NULL OR m.valido_ate > now())
   ORDER BY m.definido_em DESC LIMIT 1;
  IF EXISTS (SELECT 1 FROM nai_fechamento f WHERE f.contato_id = ANY (v_ids) AND f.concluido_em IS NULL
               AND (v_em IS NULL OR f.iniciado_em >= v_em)) THEN
    RETURN 'fechamento_com_a_rayssa';
  END IF;
  IF EXISTS (SELECT 1 FROM nai_visita v WHERE v.corretor_id = ANY (v_ids) AND nai_visita_com_a_rayssa(v.estado, v.quando)
               AND (v_em IS NULL OR v.atualizado_em > v_em)) THEN
    RETURN 'visita_com_a_rayssa';
  END IF;
  IF v_etapa = 'visitas' THEN RETURN 'visita_manual_com_a_rayssa'; END IF;
  IF v_etapa = 'fechamento' THEN RETURN 'fechamento_com_a_rayssa'; END IF;
  IF v_etapa = 'proprietarios' THEN RETURN 'proprietario_com_a_rayssa'; END IF;
  IF v_etapa = 'todos' THEN RETURN NULL; END IF;
  IF p_papel = 'proprietario' OR nai_e_proprietario_contato(p_contato) THEN
    RETURN 'proprietario_com_a_rayssa';
  END IF;
  RETURN NULL;
END $function$;
