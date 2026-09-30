-- OS QUATRO GRUPOS DE MAIOR MOVIMENTO, sob um apelido só (Tel, 27/09)
--
-- O PEDIDO, literal: "tem uns grupos que o movimento é maior que vou postar
-- todo dia uns imóveis neles" -- e os quatro nomes, seguidos de
-- "posta 5713 no grupo lotado todo dia as 12:30".
--
-- É O PRIMEIRO APELIDO COM MAIS DE UM GRUPO. Easy, Alto Padrão e Comercial
-- são um cada; "lotado" são quatro. `grupos_com_apelido` já devolvia lista e
-- `_postar_easy` já percorria, então a estrutura aguenta -- o que muda é a
-- redação das respostas, que passam a falar em "grupos" no plural.
--
-- MEDIDO ANTES DE MARCAR: `apelido` não entra em nenhum outro filtro. O
-- `montar_lista_destinos` (o `posta o NNNN` de sempre) seleciona por
-- `todas_fotos` e pelas regras de valor; o disparo de lista para parceiros,
-- por `todas_fotos` e `aceita_*`. Então estes quatro continuam recebendo
-- exatamente o que já recebem -- o apelido só abre a porta nova.
--
-- OS QUATRO, conferidos na tabela em 27/09: todos `ativo`, `todas_fotos=f`
-- (recebem a metadinha, uma imagem), `aceita_venda` e `aceita_locacao`, sem
-- piso de valor, sem `so_condominio` e sem `so_comercial`. Por isso a
-- postagem por apelido não precisa de parede de tipo nem de faixa aqui.
--
-- Casamento por ID, nunca por nome: os nomes têm emoji, barra vertical e
-- espaço duplo, e um LIKE errado marcaria o grupo errado.

-- A TRAVA DE APELIDO ÚNICO PRECISA ABRIR -- SÓ PARA ESTE.
-- `grupos_apelido_unico` garantia um grupo por apelido, e a garantia é boa:
-- um segundo grupo marcado 'easy' faria o comando do Easy postar nos dois,
-- sem ninguém pedir. Ela continua valendo para easy, alto_padrao e comercial.
-- O que muda é que "lotado" é COLETIVO por definição -- são quatro grupos, e
-- é esse o pedido. A lista de exceções fica escrita aqui, à vista de quem
-- ler: quem quiser um quinto apelido coletivo tem que passar por esta linha
-- e decidir de propósito.

BEGIN;

DROP INDEX IF EXISTS grupos_apelido_unico;

CREATE UNIQUE INDEX grupos_apelido_unico
    ON grupos (apelido)
 WHERE apelido IS NOT NULL AND apelido NOT IN ('lotado');

UPDATE grupos SET apelido = 'lotado'
 WHERE id_grupo IN (
        '120363179394595348-group',  -- 📍CREDENCIADOS | Corretores Performance
        '559281275642-1489427335',   -- Top imóveis venda e aluguéis 💰💰
        '559292480860-1593617766',   -- Novos Negócios Imobiliários - AM
        '559291005912-1609266311'    -- FECHANDO PARCERIAS 1.0
   )
   AND coalesce(apelido, '') = '';

-- A reserva, igual à do Easy: um código entra uma vez, e o "de novo" (que é
-- como a grade dispara) renova depois de 10 minutos.
CREATE TABLE IF NOT EXISTS lotado_publicacoes (
    codigo       text PRIMARY KEY,
    publicado_em timestamptz NOT NULL DEFAULT now()
);

COMMIT;

SELECT nome, apelido FROM grupos WHERE apelido = 'lotado' ORDER BY nome;
