-- 591 (Pedro, 04/11/2026: "tem uns imóveis que ela cadastra mas não está colocando os dados completos, como condomínio e
-- andar; precisa ter o condomínio obrigatório; checa lá os que não têm e põe baseado nas informações que temos").
-- Só as sugestões de confiança ALTA da revisão de 04/11 (o anúncio da OLX, a descrição, o logradouro, a conversa do corretor
-- ou a ficha do grupo de cadastro dizem o condomínio): 34 imóveis ganham condo_id e o nome oficial da tabela.
-- O que era fica em privado.imovel_condominio_antes_591 (para desfazer). As de confiança média e baixa, os conflitos de
-- tipo/bairro e os condomínios que faltam na tabela esperam o Pedro.
BEGIN;

CREATE TABLE IF NOT EXISTS privado.imovel_condominio_antes_591 AS
SELECT i.codigo, i.condo_id, i.condominio_nome, now() AS guardado_em FROM imoveis i WHERE false;

WITH novo(codigo, condo) AS (VALUES
  (2741, 601),
  (2845, 572),
  (3382, 643),
  (3700, 615),
  (3721, 657),
  (3727, 657),
  (3785, 653),
  (3931, 671),
  (9056, 826),
  (9065, 426),
  (9069, 213),
  (9074, 213),
  (9075, 541),
  (9076, 541),
  (9083, 280),
  (9084, 232),
  (9090, 389),
  (9094, 37),
  (9098, 451),
  (9099, 97),
  (9103, 451),
  (9105, 451),
  (9106, 281),
  (9111, 97),
  (9113, 188),
  (9114, 679),
  (9115, 676),
  (9119, 503),
  (9121, 312),
  (9127, 115),
  (9128, 609),
  (9129, 188),
  (9130, 329),
  (9131, 280))
INSERT INTO privado.imovel_condominio_antes_591 (codigo, condo_id, condominio_nome, guardado_em)
SELECT i.codigo, i.condo_id, i.condominio_nome, now() FROM imoveis i JOIN novo n ON n.codigo = i.codigo;

WITH novo(codigo, condo) AS (VALUES
  (2741, 601),
  (2845, 572),
  (3382, 643),
  (3700, 615),
  (3721, 657),
  (3727, 657),
  (3785, 653),
  (3931, 671),
  (9056, 826),
  (9065, 426),
  (9069, 213),
  (9074, 213),
  (9075, 541),
  (9076, 541),
  (9083, 280),
  (9084, 232),
  (9090, 389),
  (9094, 37),
  (9098, 451),
  (9099, 97),
  (9103, 451),
  (9105, 451),
  (9106, 281),
  (9111, 97),
  (9113, 188),
  (9114, 679),
  (9115, 676),
  (9119, 503),
  (9121, 312),
  (9127, 115),
  (9128, 609),
  (9129, 188),
  (9130, 329),
  (9131, 280))
UPDATE imoveis i SET condo_id = c.id, condominio_nome = c.nome
  FROM novo n JOIN condominios c ON c.id = n.condo
 WHERE i.codigo = n.codigo AND (i.condo_id IS DISTINCT FROM c.id OR i.condominio_nome IS DISTINCT FROM c.nome);

COMMIT;
