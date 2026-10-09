CREATE OR REPLACE FUNCTION public.nay_saida_responder(p_turno bigint, p_contato bigint, p_texto text, p_citado text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  r        record;
  p        record;
  v_ok     text[] := '{}';
  v_voltou text[] := '{}';
  v_restam text[];
  v_msg    text := '';
  v_val    interval := make_interval(hours => greatest(nai_cfg_int('aviso_saida_validade_h', 24), 1));
BEGIN
  SELECT * INTO r FROM nay_saida_resposta_ler(p_contato, p_texto, p_citado);
  IF NOT FOUND THEN RETURN NULL; END IF;

  FOR p IN
    SELECT q.id, q.codigo, coalesce(a.motivo, q.motivo) AS motivo,
           coalesce((SELECT i.disponivel FROM imoveis i WHERE i.codigo::text = q.codigo), true) AS disponivel
      FROM aviso_de_saida_pergunta q
      JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
     WHERE q.id = ANY (r.ids)
     ORDER BY q.id
       FOR UPDATE OF q
  LOOP
    IF p.disponivel THEN
      -- voltou a ficar disponível antes da resposta: não há o que avisar
      UPDATE aviso_de_saida_pergunta SET resposta = 'vencida', respondido_em = now(), turno_id = p_turno WHERE id = p.id;
      v_voltou := array_append(v_voltou, p.codigo);
    ELSE
      UPDATE aviso_de_saida_pergunta SET resposta = r.resposta, respondido_em = now(), turno_id = p_turno WHERE id = p.id;
      v_ok := array_append(v_ok, nay_saida_rotulo(p.codigo, p.motivo));
    END IF;
  END LOOP;

  IF cardinality(v_ok) > 0 THEN
    v_msg := CASE WHEN r.resposta = 'sim' THEN 'Combinado, aviso no grupo Easy: ' ELSE 'Combinado, não aviso no grupo: ' END
             || array_to_string(v_ok, '; ') || '.';
  END IF;
  IF cardinality(v_voltou) > 0 THEN
    v_msg := v_msg || E'\n' || 'Voltou a ficar disponível, então não tem aviso: ' || array_to_string(v_voltou, ', ') || '.';
  END IF;
  IF cardinality(r.sem_pergunta) > 0 THEN
    v_msg := v_msg || E'\n' || 'Não tenho pergunta de aviso em aberto para: ' || array_to_string(r.sem_pergunta, ', ') || '.';
  END IF;

  SELECT array_agg(q.codigo ORDER BY q.id) INTO v_restam
    FROM aviso_de_saida_pergunta q
    JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
   WHERE q.contato_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))
     AND q.resposta IS NULL AND a.avisado_em IS NULL AND q.perguntado_em > now() - v_val;
  IF v_restam IS NOT NULL THEN
    v_msg := v_msg || E'\n' || 'Ainda sem resposta: ' || array_to_string(v_restam, ', ')
             || '. Responda SIM ' || v_restam[1] || ', NÃO ' || v_restam[1] || ' ou SIM TODOS.';
  END IF;
  RETURN btrim(v_msg, E' \n');
END
$function$;
