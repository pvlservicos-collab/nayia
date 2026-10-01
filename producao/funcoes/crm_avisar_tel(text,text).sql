CREATE OR REPLACE FUNCTION public.crm_avisar_tel(p_texto text, p_origem text)
 RETURNS TABLE(ok boolean, mensagem text, restam_na_hora integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_origem text := left(coalesce(nullif(regexp_replace(coalesce(p_origem, ''), '[^[:alnum:] _.-]', '', 'g'), ''), 'robô'), 30);
  v_texto  text := btrim(regexp_replace(coalesce(p_texto, ''), '[\x00-\x08\x0B\x0C\x0E-\x1F]', '', 'g'));
  v_hora   int  := nai_cfg_int('aviso_externo_por_hora', 12);
  v_dia    int  := nai_cfg_int('aviso_externo_por_dia', 60);
  n_hora   int;
  n_dia    int;
  v_saida  bigint;
  v_motivo text;
BEGIN
  -- um robô em laço manda duas ao mesmo tempo: uma de cada vez
  PERFORM pg_advisory_xact_lock(hashtext('aviso_externo'));
  SELECT count(*) FILTER (WHERE criado_em > now() - interval '1 hour'),
         count(*) FILTER (WHERE criado_em > now() - interval '1 day')
    INTO n_hora, n_dia
    FROM aviso_externo WHERE aceito AND criado_em > now() - interval '1 day';

  v_motivo := CASE
    WHEN length(v_texto) < 3 THEN 'mensagem vazia'
    WHEN length(v_texto) > 1200 THEN 'mensagem longa demais (máximo 1200 caracteres)'
    WHEN EXISTS (SELECT 1 FROM aviso_externo a
                  WHERE a.aceito AND a.origem = v_origem AND a.criado_em > now() - interval '30 minutes'
                    AND lower(btrim(a.texto)) = lower(v_texto)) THEN 'repetida: essa mesma mensagem já saiu há menos de 30 minutos'
    WHEN n_hora >= v_hora THEN 'limite de ' || v_hora || ' avisos por hora'
    WHEN n_dia  >= v_dia  THEN 'limite de ' || v_dia  || ' avisos por dia'
  END;

  IF v_motivo IS NOT NULL THEN
    INSERT INTO aviso_externo (origem, texto, aceito, motivo) VALUES (v_origem, left(v_texto, 1200), false, v_motivo);
    RETURN QUERY SELECT false, 'Não mandei: ' || v_motivo || '.', greatest(0, v_hora - n_hora);
    RETURN;
  END IF;

  v_saida := nai_avisar_tel(NULL, NULL, 'Aviso do ' || v_origem || ': ' || v_texto, 'aviso_externo');
  INSERT INTO aviso_externo (origem, texto, aceito, saida_id) VALUES (v_origem, v_texto, true, v_saida);
  RETURN QUERY SELECT true, 'Mandei ao Tel.'::text, greatest(0, v_hora - n_hora - 1);
END $function$;
