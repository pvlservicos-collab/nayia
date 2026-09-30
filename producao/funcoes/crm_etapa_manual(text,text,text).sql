CREATE OR REPLACE FUNCTION public.crm_etapa_manual(p_telefone text, p_etapa text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_contato bigint;
  v_ids     bigint[];
  v_quem    text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
BEGIN
  IF p_etapa NOT IN ('todos', 'visitas', 'proprietarios', 'fechamento', 'tel', 'rayssa', 'soltar') THEN
    RETURN QUERY SELECT false, 'Etapa desconhecida: ' || coalesce(p_etapa, '');
    RETURN;
  END IF;
  SELECT id INTO v_contato FROM nai_contato WHERE chave = nai_chave(p_telefone);
  IF v_contato IS NULL THEN
    RETURN QUERY SELECT true, 'A Nay ainda não conversou com esse número: nada a mudar do lado dela.'::text;
    RETURN;
  END IF;
  v_ids := coalesce(nai_contato_irmaos(v_contato), ARRAY[v_contato]);

  IF p_etapa = 'tel' THEN
    UPDATE nai_contato SET humano_assumiu_em = now(), humano_motivo = left('CRM: ' || v_quem || ' mandou para o Tel', 200)
     WHERE id = ANY (v_ids);  -- 215: as duas linhas da pessoa
    RETURN QUERY SELECT true, 'Com o Tel: a Nay não responde até o Tel devolver.'::text;
    RETURN;
  END IF;
  -- 208: a Rayssa, pelo mesmo caminho; "Rayssa: " na frente é o que o CRM lê
  IF p_etapa = 'rayssa' THEN
    UPDATE nai_contato SET humano_assumiu_em = now(),
                           humano_motivo = left('Rayssa: CRM: ' || v_quem || ' mandou para a Rayssa', 200)
     WHERE id = ANY (v_ids);  -- 215: as duas linhas da pessoa
    RETURN QUERY SELECT true, 'Com a Rayssa: a Nay não responde até a conversa voltar para Todos.'::text;
    RETURN;
  END IF;
  -- 212: o × da etiqueta -- só tira a marca de humano, sem mexer em etapa nem fechamento
  IF p_etapa = 'soltar' THEN
    UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_ids);
    RETURN QUERY SELECT true, CASE WHEN nai_com_a_rayssa(v_contato, NULL) IS NULL
      THEN 'Etiqueta tirada: a Nay volta a responder.'
      ELSE 'Etiqueta tirada. A conversa continua em Visitas, Proprietários ou Fechamento: a Nay segue calada.' END;
    RETURN;
  END IF;

  INSERT INTO nai_etapa_manual (contato_id, etapa, definido_por, definido_em, valido_ate)
  VALUES (v_contato, p_etapa, v_quem, now(), CASE WHEN p_etapa = 'visitas' THEN now() + interval '7 days' END)
  ON CONFLICT (contato_id) DO UPDATE SET etapa = EXCLUDED.etapa, definido_por = EXCLUDED.definido_por,
    definido_em = EXCLUDED.definido_em, valido_ate = EXCLUDED.valido_ate;
  DELETE FROM nai_etapa_manual WHERE contato_id = ANY (v_ids) AND contato_id <> v_contato;

  IF p_etapa = 'fechamento' THEN
    INSERT INTO nai_fechamento (contato_id, iniciado_por) VALUES (v_contato, v_quem) ON CONFLICT DO NOTHING;
  ELSIF p_etapa = 'todos' THEN
    UPDATE nai_fechamento SET concluido_em = now(), concluido_por = v_quem
     WHERE contato_id = ANY (v_ids) AND concluido_em IS NULL;
    UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_ids);
  END IF;
  RETURN QUERY SELECT true, CASE p_etapa
    WHEN 'visitas' THEN 'Em Visitas: quem atende é a Rayssa; a Nay não responde (7 dias ou até voltar para Todos).'
    WHEN 'fechamento' THEN 'Em Fechamento: quem atende é a Rayssa até ela concluir.'
    WHEN 'proprietarios' THEN 'Em Proprietários: a Nay não responde.'
    ELSE 'Em Todos: a Nay volta a atender.' END;
END $function$;
