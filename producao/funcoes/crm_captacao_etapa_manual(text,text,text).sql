CREATE OR REPLACE FUNCTION public.crm_captacao_etapa_manual(p_telefone text, p_etapa text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_dig  text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_quem text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
  v_n    int;
BEGIN
  IF length(v_dig) IN (10, 11) THEN v_dig := '55' || v_dig; END IF;
  IF v_dig !~ '^[0-9]{12,13}$' THEN
    RETURN QUERY SELECT false, 'Não entendi o telefone.'; RETURN;
  END IF;
  IF p_etapa NOT IN ('todos', 'em_andamento', 'followup', 'disponiveis', 'alugados',
                     'quer_vender', 'ja_vendeu', 'tem_outro_imovel', 'sem_resposta', 'com_o_tel') THEN
    RETURN QUERY SELECT false, 'Etapa desconhecida: ' || coalesce(p_etapa, ''); RETURN;
  END IF;

  IF p_etapa = 'todos' THEN
    DELETE FROM captacao_etapa_manual WHERE telefone = v_dig;
    UPDATE captacao_leads SET humano_assumiu_em = NULL, humano_motivo = NULL
     WHERE right(telefone, 8) = right(v_dig, 8) AND humano_assumiu_em IS NOT NULL;
    RETURN QUERY SELECT true, 'Em Todos: a etapa volta a ser a que a campanha diz.';
    RETURN;
  END IF;

  INSERT INTO captacao_etapa_manual (telefone, etapa, definido_por)
  VALUES (v_dig, p_etapa, v_quem)
  ON CONFLICT (telefone) DO UPDATE SET etapa = EXCLUDED.etapa, definido_por = EXCLUDED.definido_por, definido_em = now();

  -- com o Tel: a Nay para de responder essa pessoa (o mesmo da Parceria)
  IF p_etapa = 'com_o_tel' THEN
    UPDATE captacao_leads
       SET humano_assumiu_em = coalesce(humano_assumiu_em, now()),
           humano_motivo = coalesce(humano_motivo, left('CRM: ' || v_quem || ' mandou para o Tel', 200))
     WHERE right(telefone, 8) = right(v_dig, 8);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN QUERY SELECT true, CASE WHEN v_n > 0
      THEN 'Com o Tel: a Nay não fala mais com essa pessoa até voltar para Todos.'
      ELSE 'Com o Tel. (Essa pessoa não está na campanha, então não havia nada para calar.)' END;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'Movido para ' || CASE p_etapa
    WHEN 'em_andamento' THEN 'Em andamento' WHEN 'followup' THEN 'Follow-up'
    WHEN 'disponiveis' THEN 'Disponíveis'  WHEN 'alugados' THEN 'Alugados'
    WHEN 'quer_vender' THEN 'Quer vender'  WHEN 'ja_vendeu' THEN 'Já vendeu'
    WHEN 'tem_outro_imovel' THEN 'Tem outro imóvel' ELSE 'Sem resposta' END || '.';
END $function$;
