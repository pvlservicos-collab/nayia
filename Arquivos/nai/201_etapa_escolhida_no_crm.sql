-- 201 (Pedro, 30/09/2026): A ESCOLHA FEITA À MÃO NO CRM VALE PARA A NAY.
-- "a Rayssa pode subir corretores manualmente para a aba Visitas, que são aqueles
--  que ainda não confirmaram e estão em etapa de organização de um horário" e
-- "tudo que for dúvida ou estranho vai para a aba Tel no CRM, que ele vai julgar".
-- Até aqui a etapa escolhida no card do CRM (custom_attributes) a Nay não via:
-- pôr alguém em Visitas pela tela não calava a Nay.
--
-- crm_etapa_manual(telefone, etapa, quem), chamada pelo CRM quando alguém escolhe:
--   visitas       a Rayssa atende (7 dias, ou até voltar para Todos)
--   fechamento    abre nai_fechamento (a Rayssa conclui)
--   proprietarios a Nay não responde
--   todos         a Nay volta a atender: conclui o fechamento aberto e tira a marca de Tel
--   tel           o Tel com a conversa (aparece na aba Tel; a Nay calada até o DEVOLVER)
-- A mão manda sobre o que a Nay deduz; mas uma visita confirmada ou um checklist
-- DEPOIS da escolha à mão voltam a valer (a escolha é daquele momento).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS nai_etapa_manual (
  contato_id    bigint PRIMARY KEY REFERENCES nai_contato(id),
  etapa         text NOT NULL CHECK (etapa IN ('todos', 'visitas', 'proprietarios', 'fechamento')),
  definido_por  text,
  definido_em   timestamptz NOT NULL DEFAULT now(),
  valido_ate    timestamptz
);

CREATE OR REPLACE FUNCTION nai_com_a_rayssa(p_contato bigint, p_papel text)
 RETURNS text LANGUAGE plpgsql STABLE AS $$
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
END $$;

CREATE OR REPLACE FUNCTION crm_etapa_manual(p_telefone text, p_etapa text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_contato bigint;
  v_ids     bigint[];
  v_quem    text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
BEGIN
  IF p_etapa NOT IN ('todos', 'visitas', 'proprietarios', 'fechamento', 'tel') THEN
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
     WHERE id = v_contato;
    RETURN QUERY SELECT true, 'Com o Tel: a Nay não responde até o Tel devolver.'::text;
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
END $$;

GRANT EXECUTE ON FUNCTION crm_etapa_manual(text, text, text) TO nay_disparo;
COMMIT;
