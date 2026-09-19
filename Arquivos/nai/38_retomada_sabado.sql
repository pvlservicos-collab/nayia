-- =====================================================================
-- NAI -- 38: a retomada de sabado 19/09 08:45 (Tel, 18/09/2026 23h)
--
-- Nas palavras dele: "a partir de amanha sabado 19 de setembro as 8:45 da
-- manha vai comecar a responder quem nao foi respondido sobre imoveis, mas
-- esta na lista de corretores ... se nao [falar de imovel], nao precisa
-- responder ... agenda para mim esse ligamento amanha pela manha."
-- E depois: "mesmo se a pessoa estiver na lista, se ela recebeu uma mensagem
-- do Tel nas ultimas 16 horas a Nay vai ignorar tambem ... coloca essa regra
-- SO PARA AMANHA."
--
-- POR ISSO ESTA TABELA EXISTE, e nao um `nai_config` novo: a regra das 16h e
-- de UM DIA. Config nova seria uma regra permanente que alguem esqueceria
-- ligada. Aqui ela morre com a tabela.
--
-- `responder` guarda a leitura HUMANA de cada mensagem -- a peneira automatica
-- (`nai_pergunta_de_imovel`) diz "fala de imovel", mas nao distingue PERGUNTA
-- de ANUNCIO: corretor divulgando imovel dele, ou disparando marketing para a
-- lista, passa pela peneira. Essas ficam com responder = false.
--
-- O trabalho das 8:45 CONFERE DE NOVO, na hora: a lista (`nai_pode_falar`),
-- o gap do Tel e as 16 horas. Uma mensagem que chegar de madrugada e uma
-- conversa que o Tel assumir as 7h mudam o resultado, e tem que mudar.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS nai_retomada (
  chave       text PRIMARY KEY,
  telefone    text NOT NULL,
  nome        text,
  texto       text,
  recebida_em timestamptz,
  responder   boolean NOT NULL DEFAULT true,
  motivo      text,
  estado      text NOT NULL DEFAULT 'pendente'
              CHECK (estado IN ('pendente','enviado','pulado','erro')),
  pulo        text,
  rodado_em   timestamptz
);

COMMENT ON TABLE nai_retomada IS
  'Fila de uma vez so: as conversas sem resposta que a NAI vai retomar no sabado 19/09 08:45. Descartavel depois.';

TRUNCATE nai_retomada;

INSERT INTO nai_retomada (chave, telefone, nome, texto, recebida_em)
WITH rec AS (
  SELECT DISTINCT ON (nai_chave(telefone))
         nai_chave(telefone) AS chave, telefone, nome, texto, criada_em
    FROM mensagens
   WHERE direcao = 'recebida' AND criada_em > now() - interval '10 days'
   ORDER BY nai_chave(telefone), criada_em DESC
), env AS (
  SELECT nai_chave(telefone) AS chave, max(criada_em) AS quando
    FROM mensagens
   WHERE direcao = 'enviada' AND criada_em > now() - interval '10 days'
   GROUP BY 1
)
SELECT r.chave, r.telefone, r.nome, r.texto, r.criada_em
  FROM rec r
  LEFT JOIN env e ON e.chave = r.chave
  LEFT JOIN nai_contato k ON k.chave = r.chave
 WHERE (e.quando IS NULL OR e.quando < r.criada_em)
   AND nai_pode_falar(r.chave, r.telefone)
   AND nai_pergunta_de_imovel(r.texto, r.telefone, NULL)
   AND NOT nai_tel_com_a_conversa(k.id);

-- ---------------------------------------------------------------------
-- A LEITURA HUMANA: anuncio e marketing nao sao pergunta para a gente.
-- ---------------------------------------------------------------------
UPDATE nai_retomada SET responder = false, motivo = 'anuncio de imovel do proprio corretor, nao e pergunta para nos'
 WHERE texto ~* '^\s*(🏠|📍)' OR texto ~* '\m(alugo|vendo|repasso)\M';

UPDATE nai_retomada SET responder = false, motivo = 'marketing disparado para lista de corretores'
 WHERE texto ~* 'NOVIDADE PARA CORRETORES|conte com a|parceria premiada';

UPDATE nai_retomada SET responder = false, motivo = 'recado, nao pergunta -- nao espera resposta'
 WHERE texto ~* 'aguardando cliente|ja achei aqui';

COMMIT;

SELECT responder, count(*), string_agg(left(coalesce(nome,'—'), 18), ' · ') AS quem
  FROM nai_retomada GROUP BY 1 ORDER BY 1 DESC;
