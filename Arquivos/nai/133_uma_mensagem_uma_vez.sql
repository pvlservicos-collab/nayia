-- =====================================================================
-- 133 — UMA MENSAGEM, UMA VEZ (27/09/2026)
--
-- Pedido: "IMPLEMENTA UMA FILA MELHOR", depois de o 3210 chegar três vezes ao
-- 92 8110-1119 a partir de uma única mensagem do Tel.
--
-- O DEFEITO DA FILA: ela guarda uma linha por ENTREGA do webhook, não por
-- MENSAGEM do WhatsApp. A reserva (`Reservar mensagens`, UPDATE ... RETURNING)
-- já garante que cada LINHA é atendida uma vez só -- o problema é que a mesma
-- mensagem virava várias linhas:
--
--   * a Z-API reentrega quando o n8n demora a responder (fila de 5 cheia);
--   * o fluxo antigo repassa para a NAI com 10s de prazo e, estourando, cai no
--     caminho DELE -- mas a NAI tinha recebido, e atende 4 minutos depois;
--   * a Z-API manda de novo a mesma imagem ~40 min depois, como 'outro'.
--
-- MEDIDO NOS ÚLTIMOS 14 DIAS: 205 textos e 42 áudios atendidos pelos DOIS
-- fluxos, e ~400 mensagens com mais de uma linha, de 6.488. Não foi só o
-- 3210: corretor recebendo resposta dobrada era rotina.
--
-- A CORREÇÃO MORA NA GRAVAÇÃO, NÃO NO n8n: os dois fluxos gravam na mesma
-- `mensagens`, e as duas consultas "Gravar na fila" terminam em `FROM ins`.
-- Recusando a segunda cópia aqui, o INSERT volta zero linhas, o nó não emite
-- item nenhum e aquele fluxo para ali mesmo -- sem erro e sem alarme.
-- Quem gravou primeiro atende; o outro desiste calado.
--
-- SÓ ID DE VERDADE: o WhatsApp gera hexadecimal maiúsculo de 20 a 32
-- caracteres (5.087 de 5.087 em 14 dias). Os ids de teste -- TREINO…,
-- BLOCO…, PF-1 do pré-voo (que se repete de propósito a cada rodada),
-- TESTE… -- não têm esse formato e passam como sempre passaram. Uma trava
-- que barra o teste mata a rodada inteira (rodada 12).
--
-- O QUE FOI BARRADO FICA ANOTADO em `mensagem_repetida`, para dar para medir
-- se a fila está segurando -- e de qual fluxo vinha a cópia.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS mensagem_repetida (
  id          bigserial PRIMARY KEY,
  message_id  text        NOT NULL,
  telefone    text,
  fluxo       text,
  origem      text,
  -- a linha que ficou valendo
  primeira_id bigint,
  barrada_em  timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION mensagens_uma_vez_so()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_primeira bigint;
BEGIN
  IF NEW.direcao IS DISTINCT FROM 'recebida'
     OR NEW.message_id IS NULL
     OR NEW.message_id !~ '^[0-9A-F]{16,40}$' THEN
    RETURN NEW;
  END IF;

  -- Duas cópias chegando juntas: a segunda espera a primeira gravar, e só
  -- então olha. Sem isso as duas olhariam ao mesmo tempo e passariam.
  PERFORM pg_advisory_xact_lock(hashtext('mensagem:' || NEW.message_id));

  SELECT m.id INTO v_primeira
    FROM mensagens m
   WHERE m.message_id = NEW.message_id
     AND m.direcao = 'recebida'
     AND m.criada_em > now() - interval '2 days'
   ORDER BY m.id
   LIMIT 1;

  IF v_primeira IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO mensagem_repetida (message_id, telefone, fluxo, origem, primeira_id)
  VALUES (NEW.message_id, NEW.telefone, coalesce(NEW.fluxo, 'antigo'), NEW.origem, v_primeira);
  RETURN NULL;
END;
$fn$;

DROP TRIGGER IF EXISTS mensagens_uma_vez_so ON mensagens;
CREATE TRIGGER mensagens_uma_vez_so
  BEFORE INSERT ON mensagens
  FOR EACH ROW EXECUTE FUNCTION mensagens_uma_vez_so();

COMMIT;
