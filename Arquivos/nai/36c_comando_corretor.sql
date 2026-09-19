-- =====================================================================
-- NAI -- 36c: CORRETOR / NAO CORRETOR, e a pergunta ao Tel (18/09/2026)
--
-- Quando alguem de FORA da lista pergunta de imovel, a porta (36b) cala e
-- devolve o motivo "fora da lista: perguntou de imovel, perguntar ao Tel". O
-- gatilho abaixo le esse motivo no turno recem-criado e pergunta ao Tel -- UMA
-- vez por pessoa. A porta roda antes de o turno existir, por isso a pergunta
-- sai daqui e nao de dentro dela.
--
-- O Tel responde no pv da NAI:
--   CORRETOR 92 99999-8888       -> entra na lista, ela atende dali em diante
--   NAO CORRETOR 92 99999-8888   -> ela nunca responde essa pessoa
-- A decisao dele vale mais que o grupo, e a sincronizacao semanal nao desfaz.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- E comando de corretor? Exige o numero logo depois: "corretor aqui, tem apto?"
-- nao pode virar comando.
CREATE OR REPLACE FUNCTION nai_e_comando_corretor(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(p, '') ~* '^\s*(n[aã]o\s+)?corretor\s+[\d(+]';
$$;

-- A lista de comandos extras ganha este. Mesma funcao que o roteador le.
CREATE OR REPLACE FUNCTION nai_e_comando_extra(p text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT nai_e_comando_agenda(p) OR nai_e_comando_parada(p) OR nai_e_comando_corretor(p);
$$;

-- A decisao do Tel. Devolve a frase que volta para ele.
CREATE OR REPLACE FUNCTION nai_decidir_corretor(p_fone text, p_e_corretor boolean)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_chave text := nai_chave(p_fone);
  v_dig   text := regexp_replace(coalesce(p_fone, ''), '\D', '', 'g');
  v_nome  text;
BEGIN
  IF v_chave IS NULL OR v_chave ~ '^lid:' THEN
    RETURN 'Não entendi o telefone. Use: CORRETOR 92 99999-8888  ou  NAO CORRETOR 92 99999-8888';
  END IF;
  -- sem DDI, completa com 55: e assim que o corretores guarda
  IF length(v_dig) IN (10, 11) THEN v_dig := '55' || v_dig; END IF;

  SELECT coalesce(c.nome_completo, c.nome_whatsapp) INTO v_nome
    FROM nai_contato c WHERE c.chave = v_chave;

  INSERT INTO nai_corretor_pergunta (chave, telefone, nome, decisao, decidido_em)
  VALUES (v_chave, v_dig, v_nome, CASE WHEN p_e_corretor THEN 'sim' ELSE 'nao' END, now())
  ON CONFLICT (chave) DO UPDATE
     SET decisao = EXCLUDED.decisao, decidido_em = EXCLUDED.decidido_em;

  IF p_e_corretor THEN
    -- Ja existe (com ou sem o nono digito)? Atualiza. Senao, entra.
    UPDATE corretores
       SET pode_falar = true, aprovado = true, ativo = true, fonte = 'tel'
     WHERE nai_chave(telefone) = v_chave;
    IF NOT FOUND THEN
      INSERT INTO corretores (telefone, nome, origem, aprovado, ativo, pode_falar, fonte)
      VALUES (v_dig, v_nome, 'aprovado pelo Tel em ' || to_char(now(), 'DD/MM'),
              true, true, true, 'tel')
      ON CONFLICT (telefone) DO UPDATE
         SET pode_falar = true, aprovado = true, ativo = true, fonte = 'tel';
    END IF;
    RETURN 'Feito: ' || nai_fone_fmt(v_dig) || coalesce(' (' || v_nome || ')', '')
        || ' agora é corretor. A NAI atende a partir da próxima mensagem dele.';
  END IF;

  UPDATE corretores SET pode_falar = false WHERE nai_chave(telefone) = v_chave;
  RETURN 'Feito: a NAI não responde mais ' || nai_fone_fmt(v_dig)
      || coalesce(' (' || v_nome || ')', '')
      || '. Para voltar atrás: CORRETOR ' || nai_fone_fmt(v_dig);
END;
$$;

-- ---------------------------------------------------------------------
-- A PERGUNTA AO TEL -- gatilho no turno
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_perguntar_se_e_corretor()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  c        nai_contato;
  v_nova   boolean;
  v_texto  text;
BEGIN
  SELECT * INTO c FROM nai_contato WHERE id = NEW.contato_id;
  IF c.id IS NULL THEN RETURN NEW; END IF;

  -- So a PRIMEIRA vez. Se ja perguntou, a porta ja devolveu "esperando o Tel".
  INSERT INTO nai_corretor_pergunta (chave, telefone, nome, ultimo_texto, turno_id)
  VALUES (c.chave, c.telefone, coalesce(c.nome_completo, c.nome_whatsapp), left(NEW.texto, 300), NEW.id)
  ON CONFLICT (chave) DO NOTHING
  RETURNING true INTO v_nova;

  IF NOT coalesce(v_nova, false) THEN RETURN NEW; END IF;

  -- Sem emoji: texto que sai de funcao nao passa pelo filtro do modelo.
  v_texto := 'Chegou mensagem de quem NÃO está nos grupos de corretores:' || E'\n\n'
          || coalesce(nullif(btrim(coalesce(c.nome_completo, c.nome_whatsapp, '')), ''), 'sem nome')
          || ' - ' || nai_fone_fmt(c.telefone) || E'\n'
          || '"' || left(coalesce(NEW.texto, ''), 300) || '"' || E'\n\n'
          || 'Ela não respondeu. É corretor? Responda aqui:' || E'\n'
          || 'CORRETOR ' || nai_fone_fmt(c.telefone) || '  - ela passa a atender' || E'\n'
          || 'NAO CORRETOR ' || nai_fone_fmt(c.telefone) || '  - ela nunca responde';

  PERFORM nai_avisar_tel(NEW.id, NULL, v_texto, 'corretor fora da lista');
  RETURN NEW;
EXCEPTION WHEN others THEN
  -- Este gatilho roda DENTRO do nai_abrir_turno. Se o aviso falhar, o turno do
  -- corretor nao pode morrer junto: perder a pergunta e ruim, derrubar a
  -- entrada da mensagem e pior.
  RAISE WARNING 'nai_perguntar_se_e_corretor falhou no turno %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS nai_turno_pergunta_corretor ON nai_turno;
CREATE TRIGGER nai_turno_pergunta_corretor
  AFTER INSERT ON nai_turno
  FOR EACH ROW
  WHEN (NEW.porta = 'fora da lista: perguntou de imovel, perguntar ao Tel')
  EXECUTE FUNCTION nai_perguntar_se_e_corretor();

COMMIT;
