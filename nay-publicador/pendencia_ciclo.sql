-- A pendência fecha o ciclo: todo mundo que perguntou recebe, e o Tel é
-- cobrado se esquecer.
--
-- OS DOIS BURACOS (auditoria de 31/08):
--
-- 1. `pendencias.avisar` guarda UM telefone. O segundo corretor que
--    perguntar a mesma coisa do mesmo imóvel cai no ramo `esperar`, ouve
--    "ainda estou verificando" e **não fica ligado a pendência nenhuma**.
--    Quando o Tel responde, só o primeiro recebe -- e não há registro de
--    que o segundo existiu. Ele fica esperando para sempre.
--
-- 2. Nada tem relógio. Pendência aberta fica aberta. Ninguém cobra o Tel,
--    nada volta ao corretor. O Leonan esperou dois dias por uma resposta
--    que estava na descrição do site.
--
-- COMO ISTO ENTREGA SEM MEXER NO n8n: quando o Tel responde, o primeiro
-- da fila continua recebendo pelo sub-fluxo de sempre. Os OUTROS entram
-- em `resposta_a_entregar`, e o cron `entregar_respostas.py` manda --
-- mesmas paredes do lembrete e da entrega: pausa geral, janela de horário,
-- teto de um contato por dia, reserva atômica antes de enviar.
--
-- O RELÓGIO É AJUSTÁVEL SEM DEPLOY: `config.pendencia_horas_para_cobrar`.
-- O padrão de 4 horas é chute meu, não decisão do Tel -- ele muda com um
-- UPDATE, sem import nem restart, como a pausa geral.
--
--   docker cp pendencia_ciclo.sql nay-postgres:/tmp/pc.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/pc.sql

-- --------------------------------------------------------------------
-- Quem está esperando esta resposta. O primeiro entra junto com a
-- pendência, para não existirem duas noções de "quem perguntou".
CREATE TABLE IF NOT EXISTS pendencia_interessado (
  id           bigserial PRIMARY KEY,
  pendencia_id integer NOT NULL REFERENCES pendencias(id) ON DELETE CASCADE,
  telefone     text NOT NULL,
  nome         text,
  perguntou_em timestamptz NOT NULL DEFAULT now()
);

-- Os 8 últimos dígitos, nunca o telefone cru: a Z-API entrega o mesmo
-- número ora com 12 ora com 13 dígitos, e cru a mesma pessoa entraria
-- duas vezes e receberia a resposta duas vezes.
CREATE UNIQUE INDEX IF NOT EXISTS interessado_um_por_pendencia
  ON pendencia_interessado (pendencia_id,
                            right(regexp_replace(telefone,'[^0-9]','','g'),8));

-- --------------------------------------------------------------------
-- A fila de saída. Mesma forma de `entrega_pendente`, pelo mesmo motivo:
-- ferramenta de banco não envia mensagem, quem envia é cron ou sub-fluxo.
CREATE TABLE IF NOT EXISTS resposta_a_entregar (
  id           bigserial PRIMARY KEY,
  pendencia_id integer NOT NULL REFERENCES pendencias(id) ON DELETE CASCADE,
  telefone     text NOT NULL,
  texto        text NOT NULL,
  estado       text NOT NULL DEFAULT 'devendo',
  criado_em    timestamptz NOT NULL DEFAULT now(),
  entregue_em  timestamptz,
  CONSTRAINT resposta_estado_ok CHECK (estado IN ('devendo','entregue','cancelada'))
);

CREATE UNIQUE INDEX IF NOT EXISTS resposta_uma_viva
  ON resposta_a_entregar (pendencia_id,
                          right(regexp_replace(telefone,'[^0-9]','','g'),8))
  WHERE estado = 'devendo';

-- --------------------------------------------------------------------
-- Registra quem perguntou. Chamada pelos dois ramos de `nay_escalar`.
CREATE OR REPLACE FUNCTION nay_anotar_interessado(
  p_pendencia_id integer, p_telefone text, p_nome text
) RETURNS void
LANGUAGE sql AS $fn$
  INSERT INTO pendencia_interessado (pendencia_id, telefone, nome)
  SELECT p_pendencia_id, p_telefone, NULLIF(btrim(coalesce(p_nome,'')),'')
   WHERE p_pendencia_id IS NOT NULL
     AND NULLIF(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),'') IS NOT NULL
  ON CONFLICT DO NOTHING;
$fn$;

-- --------------------------------------------------------------------
-- Responder passa a enfileirar para TODO MUNDO que perguntou, menos quem
-- já recebe pelo sub-fluxo de sempre.
-- A ASSINATURA NÃO MUDA: `nay_comando` faz `SELECT * INTO r` daqui, e
-- trocar o nome ou a ordem das colunas quebraria o RESPOSTA do Tel -- que
-- é o caminho à prova de tudo. O que muda é só o efeito colateral.
CREATE OR REPLACE FUNCTION nay_responder_pendencia(p_id integer, p_resposta text)
RETURNS TABLE(ok boolean, avisar text, codigo text, assunto text)
LANGUAGE plpgsql AS $fn$
DECLARE
  r record;
  v_texto text;
  v_outros int;
  v_esperando int := 0;
BEGIN
  UPDATE pendencias p
     SET resposta = p_resposta, status = 'respondida', respondida_em = now()
   WHERE p.id = p_id AND p.status = 'aberta'
  RETURNING p.avisar, p.codigo, p.o_que_falta INTO r;

  IF r IS NULL THEN
    RETURN QUERY SELECT false, NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;

  UPDATE escalacoes e SET status = 'resolvida', resolvida_em = now()
   WHERE e.status = 'aberta' AND e.telefone = r.avisar AND e.assunto = r.o_que_falta;

  -- Quem mais perguntou a mesma coisa e ficou esperando em silêncio.
  v_texto := 'Sobre ' ||
             CASE WHEN r.codigo IS NOT NULL THEN 'o ' || r.codigo ELSE 'o que você perguntou' END
             || ': ' || p_resposta;

  -- O LEQUE NAO CARREGA NUMERO DE UNIDADE.
  --
  -- Responder UM corretor e decisao do Tel, e ele pode ter motivo -- o
  -- cara vai fazer a visita hoje. Mandar para os OUTROS e automatico,
  -- ninguem revisa, e a lista pode ter gente que ele nem lembra que
  -- perguntou. Aqui o padrao e negar. Achado no red team de 01/09.
  IF nay_tem_numero_de_unidade(p_resposta) THEN
    v_outros := -1;   -- sinaliza que houve gente esperando e NAO recebeu
    SELECT count(*) INTO v_esperando
      FROM pendencia_interessado i
     WHERE i.pendencia_id = p_id
       AND right(regexp_replace(i.telefone,'[^0-9]','','g'),8)
         <> right(regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g'),8);
  ELSE
    INSERT INTO resposta_a_entregar (pendencia_id, telefone, texto)
    SELECT p_id, i.telefone, v_texto
      FROM pendencia_interessado i
     WHERE i.pendencia_id = p_id
       AND right(regexp_replace(i.telefone,'[^0-9]','','g'),8)
         <> right(regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g'),8)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_outros = ROW_COUNT;
  END IF;

  -- O Tel PRECISA saber que o leque nao saiu, senao ele acha que os
  -- outros foram avisados.
  RETURN QUERY SELECT true, r.avisar, r.codigo,
    r.o_que_falta || CASE WHEN v_outros = -1 AND v_esperando > 0
      THEN ' [ATENCAO: sua resposta tem numero de unidade, entao NAO foi '
           || 'repassada aos outros ' || v_esperando || ' corretor(es) que '
           || 'esperavam. So quem perguntou primeiro recebeu.]'
      ELSE '' END;
END;
$fn$;

-- --------------------------------------------------------------------
-- O que o cron precisa entregar. Mesmas paredes do lembrete.
CREATE OR REPLACE FUNCTION nay_respostas_a_entregar()
RETURNS TABLE(telefone text, ids bigint[], texto text)
LANGUAGE sql STABLE AS $fn$
  WITH ok AS (
    SELECT NOT COALESCE((SELECT valor = 'sim' FROM config
                          WHERE chave = 'atendimento_pausado'), true) AS pode
  )
  SELECT r.telefone,
         array_agg(r.id ORDER BY r.criado_em),
         string_agg(r.texto, chr(10) ORDER BY r.criado_em)
    FROM resposta_a_entregar r
   WHERE r.estado = 'devendo'
     AND (SELECT pode FROM ok)
     AND nay_pode_falar(r.telefone)
   GROUP BY r.telefone;
$fn$;

CREATE OR REPLACE FUNCTION nay_reservar_respostas(p_ids bigint[])
RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
  UPDATE resposta_a_entregar SET estado = 'entregue', entregue_em = now()
   WHERE id = ANY(p_ids) AND estado = 'devendo';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$fn$;

CREATE OR REPLACE FUNCTION nay_devolver_respostas(p_ids bigint[])
RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
  UPDATE resposta_a_entregar SET estado = 'devendo', entregue_em = NULL
   WHERE id = ANY(p_ids) AND estado = 'entregue';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$fn$;

-- --------------------------------------------------------------------
-- O RELÓGIO. Pendência aberta há tempo demais, com quantos esperam.
--
-- Devolve uma linha só, já em texto: é uma cobrança ao Tel, não um
-- relatório. Vazio significa nada atrasado, e o cron fica em silêncio.
CREATE OR REPLACE FUNCTION nay_pendencias_esquecidas()
RETURNS TABLE(quantas int, texto text)
LANGUAGE sql STABLE AS $fn$
  WITH horas AS (
    SELECT coalesce((SELECT NULLIF(valor,'')::numeric FROM config
                      WHERE chave = 'pendencia_horas_para_cobrar'), 4) AS h
  ), atrasadas AS (
    SELECT p.id, p.codigo, p.o_que_falta, p.criada_em,
           (SELECT count(*) FROM pendencia_interessado i
             WHERE i.pendencia_id = p.id) AS esperando
      FROM pendencias p
     WHERE p.status = 'aberta'
       AND p.criada_em < now() - make_interval(hours => (SELECT h FROM horas)::int)
  )
  SELECT count(*)::int,
         'Ficaram sem resposta:' || chr(10) ||
         string_agg('• ' || a.id || ' — ' ||
                    -- O NOME do imóvel, não só o código: o Tel não decora
                    -- 1.208 números. Achado na auditoria de 01/09.
                    coalesce('imóvel ' || a.codigo ||
                             coalesce(' (' || (SELECT coalesce(NULLIF(i.condominio_nome,''), i.tipo)
                                                 FROM imoveis i WHERE i.codigo::text = a.codigo) || ')', '')
                             || ' — ', '') || a.o_que_falta ||
                    ' (há ' || floor(extract(epoch FROM now() - a.criada_em)/3600)::int || 'h' ||
                    CASE WHEN a.esperando > 1
                         THEN ', ' || a.esperando || ' corretores esperando' ELSE '' END || ')',
                    chr(10) ORDER BY a.criada_em)
         || chr(10) || 'Responda com RESPOSTA <número> <texto>.'
    FROM atrasadas a
   HAVING count(*) > 0;
$fn$;

-- O padrão, para o Tel poder mudar com um UPDATE em vez de deploy.
INSERT INTO config (chave, valor) VALUES ('pendencia_horas_para_cobrar', '4')
ON CONFLICT (chave) DO NOTHING;
