-- Grupo SÓ DE IMÓVEL COMERCIAL (Tel, 15/09).
--
-- O PEDIDO: "🟢 Comercial - OFERTA e BUSCA 🔍" recebe só imóvel comercial --
-- "sala comercial, prédio comercial, galpão. nada de imóvel residencial".
--
-- O QUE É COMERCIAL sai do TIPO do cadastro, medido em 15/09: Sala, Sala/Andar,
-- Loja/Ponto, Galpão/Depósito e Prédio. A regra mora em
-- `montar_destinos.e_comercial` -- este arquivo só liga a chave no grupo.
--
-- PRÉDIO ENTRA, decisão do Tel com o risco à frente: o cadastro não diz se um
-- prédio é comercial ou residencial (o 1387 comercial tem 27 "quartos", que são
-- salas; o 3957 é uma unidade de 2 dormitórios cadastrada como Prédio, hoje fora
-- do site; o 3971 é misto). Se um prédio residencial voltar ao ar, ele vai para
-- o Comercial -- e o conserto é o tipo no admin, não aqui.
--
-- ORDEM DE DEPLOY, que aprendeu com o Alto Padrão: (1) a coluna, (2) o código,
-- (3) o INSERT do grupo, à parte. Com o grupo ativo antes do código, a grade
-- mandaria apartamento para o grupo Comercial nos minutos entre um e outro.

ALTER TABLE grupos ADD COLUMN IF NOT EXISTS so_comercial boolean NOT NULL DEFAULT false;

-- (3) SÓ DEPOIS do código novo no ar:
--   INSERT INTO grupos (id_grupo, nome, ativo, todas_fotos, limite_dia,
--                       aceita_venda, aceita_locacao, so_comercial)
--   VALUES ('120363318522560052-group', '🟢 Comercial - OFERTA e BUSCA 🔍',
--           true, false, 5, true, true, true)
--   ON CONFLICT (id_grupo) DO UPDATE SET so_comercial = true;
