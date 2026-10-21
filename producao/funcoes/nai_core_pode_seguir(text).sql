CREATE OR REPLACE FUNCTION public.nai_core_pode_seguir(p_chave text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_contato bigint;
  v_irmaos  bigint[];
  v_rayssa  text;
BEGIN
  IF nai_cfg('modo', 'desligado') <> 'todos' THEN RETURN 'nai_desligada'; END IF;
  IF nai_cfg('pausada', 'sim') <> 'nao' THEN RETURN 'pausada'; END IF;
  SELECT id INTO v_contato FROM nai_contato WHERE chave = p_chave ORDER BY id LIMIT 1;
  IF v_contato IS NULL THEN RETURN 'sem_contato'; END IF;
  v_irmaos := coalesce(nai_contato_irmaos(v_contato), ARRAY[v_contato]);
  IF nai_tel_com_a_conversa(v_contato) THEN RETURN 'tel_assumiu'; END IF;
  IF nai_gente_escreveu_ha_pouco(v_irmaos) THEN RETURN 'gente_escreveu'; END IF;
  v_rayssa := nai_com_a_rayssa(v_contato, 'corretor');
  IF v_rayssa IS NOT NULL THEN RETURN v_rayssa; END IF;
  IF NOT nai_core_atende(v_contato, '') THEN RETURN 'nao_e_do_core'; END IF;
  RETURN NULL;
END $function$;
