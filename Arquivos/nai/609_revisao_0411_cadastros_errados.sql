-- 609 (Pedro, 04/11/2026: "começa pelos erros, revisa tudo ... e faz"), da revisão das duas Nays de 04/11:
-- cadastros errados que estavam Disponíveis e podiam sair para cliente.
--   9130, 9132: a Nay Corretores juntou duas ofertas diferentes do mesmo corretor num código só
--               (9130: Smart Tarumã com aluguel 1.600 E venda 250 mil e a descrição de um imóvel do Centro;
--                9132: o nome e os quartos do Jardim Paradiso com a mobília e o preço do Conquista Torquato)
--   9139:       o corretor disse "Condomínio Bela Sonata" (Tarumã) e ficou no bairro "Turismo", sem condomínio
--   -> Rascunho, para a equipe revisar antes de voltar a Disponível
--   9019 (Liverpool): o dono disse em 04/11 08:14 que já alugou -> Alugado
--   4995 (lote Passaredo): a dona disse em 04/11 que já foi vendido -> Vendido
-- O gatilho imoveis_a_situacao_manda tira do site e da Nay quem não está Disponível. A trava (travado) impede a
-- varredura do site antigo de desfazer. Cópia de antes em privado.imoveis_antes_609.
BEGIN;
CREATE TABLE IF NOT EXISTS privado.imoveis_antes_609 AS
  SELECT now() AS copiado_em, i.* FROM imoveis i WHERE i.codigo IN (9130, 9132, 9139, 9019, 4995);

UPDATE imoveis SET status = 'Rascunho', travado = true, travado_em = now(),
       travado_motivo = 'revisão 04/11: cadastro juntou duas ofertas / condomínio errado; revisar antes de publicar'
 WHERE codigo IN (9130, 9132, 9139);
UPDATE imoveis SET status = 'Alugado', travado = true, travado_em = now(),
       travado_motivo = 'revisão 04/11: o dono disse em 04/11 que já alugou'
 WHERE codigo = 9019;
UPDATE imoveis SET status = 'Vendido', travado = true, travado_em = now(),
       travado_motivo = 'revisão 04/11: a dona disse em 04/11 que já foi vendido'
 WHERE codigo = 4995;

SELECT codigo, status, disponivel, publicado_no_site, travado FROM imoveis WHERE codigo IN (9130, 9132, 9139, 9019, 4995) ORDER BY codigo;
COMMIT;
