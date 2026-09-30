-- O GRUPO "🟢 Comercial - OFERTA e BUSCA 🔍" ganha comando próprio (Tel, 27/09).
--
-- O PEDIDO: "posta no grupo comercial 5763 (desta forma manda no grupo)".
-- Hoje essa frase vira `postar_agora` e o "no grupo comercial" é IGNORADO --
-- o imóvel sai em todos os grupos elegíveis. Medido antes de escrever.
--
-- O grupo já existe e já tem `so_comercial = true` desde 15/09 (recebe só
-- Sala, Sala/Andar, Loja/Ponto, Galpão/Depósito e Prédio). O que falta é o
-- APELIDO, que é como `grupos_com_apelido` encontra um grupo pelo nome curto.
--
--   docker cp grupo_comercial.sql nay-postgres:/tmp/gc.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/gc.sql

UPDATE grupos SET apelido = 'comercial'
 WHERE id_grupo = '120363318522560052-group'
   AND coalesce(apelido, '') = '';

-- A RESERVA ATÔMICA, igual à do Easy e à do Alto Padrão.
--
-- Não é zelo abstrato: em 25/08 o Easy postou o mesmo código duas vezes porque
-- a versão de então fazia SELECT (checa) -> busca+envia -> INSERT (grava), com
-- segundos de janela entre checar e gravar. Duas chamadas no intervalo
-- passavam as duas. Aqui o código é reservado PRIMEIRO, e quem não reservou
-- não posta.
CREATE TABLE IF NOT EXISTS comercial_publicacoes (
    codigo       text PRIMARY KEY,
    publicado_em timestamptz NOT NULL DEFAULT now()
);

SELECT '--- o grupo comercial agora ---' AS x;
SELECT id_grupo, nome, apelido, so_comercial, todas_fotos, ativo
FROM grupos WHERE apelido = 'comercial';
