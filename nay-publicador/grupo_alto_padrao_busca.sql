-- DOIS GRUPOS SE CHAMAM "ALTO PADRÃO" -- e o comando passa a ir para o outro
--
-- O PEDIDO (Tel, 27/09): "tem esse grupo 🟢 Alto Padrão - OFERTA e BUSCA 🔍
-- que vou postar todo dia uns imóveis neles", com cinco frases -- uma dizendo
-- "no grupo alto padrão" e quatro dizendo "no grupo  padrão".
--
-- A COLISÃO, medida antes de mexer:
--
--   🟢 Alto Padrão - OFERTA e BUSCA 🔍      sem apelido, uma foto, só condomínio
--   IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY  apelido alto_padrao, todas as fotos
--
-- "posta 5750 no grupo alto padrão todo dia as 12:30" caía no de ANUNCIAR
-- EASY -- o grupo errado. E "no grupo  padrão", sem o "alto", não casava nada
-- e virava postagem nos DEZESSETE grupos. Quatro das cinco frases dele.
--
-- A DECISÃO É DELE, perguntada e respondida em 27/09: "alto padrão" passa a
-- ser o OFERTA e BUSCA, e o de Anunciar Easy exige dizer "anunciar easy".
--
-- CADA GRUPO FICA COM A SUA TABELA DE RESERVA, e isto é o cuidado que não se
-- vê: se eu só trocasse o apelido, `alto_padrao_publicacoes` -- que guarda o
-- que JÁ foi postado no de Anunciar Easy desde 25/09 -- passaria a valer para
-- o OFERTA e BUSCA, e todo código já postado lá cairia em "já foi postado"
-- num grupo que nunca o recebeu. A reserva pertence ao GRUPO, não ao nome.

BEGIN;

-- 1. O de ANUNCIAR EASY sai do apelido primeiro, senão o índice único recusa
--    o segundo UPDATE. Ele CONTINUA com `alto_padrao_publicacoes`.
UPDATE grupos SET apelido = 'alto_padrao_easy'
 WHERE id_grupo = '120363431003549527-group'   -- IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY
   AND apelido = 'alto_padrao';

-- 2. E o OFERTA e BUSCA assume o nome que o Tel usa.
UPDATE grupos SET apelido = 'alto_padrao'
 WHERE id_grupo = '120363319292435731-group'   -- 🟢 Alto Padrão - OFERTA e BUSCA 🔍
   AND coalesce(apelido, '') = '';

-- 3. A reserva própria dele. O de Anunciar Easy fica com a que já tem.
CREATE TABLE IF NOT EXISTS alto_padrao_busca_publicacoes (
    codigo       text PRIMARY KEY,
    publicado_em timestamptz NOT NULL DEFAULT now()
);

COMMIT;

SELECT nome, apelido, todas_fotos, aluguel_minimo, venda_minima, so_condominio
  FROM grupos WHERE apelido LIKE 'alto_padrao%' ORDER BY apelido;
