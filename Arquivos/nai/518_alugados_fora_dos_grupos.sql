-- 518: dois imóveis ALUGADOS que seguiam "Disponível" e indo nas listas automáticas dos grupos (Pedro, 28/10/2026):
-- "tem imóveis que já foram alugados/vendidos que estão sendo ainda postados nos grupos. Dá uma olhada nisso e retira
-- das mensagens automáticas que vão para os grupos esses imóveis".
--
-- A lista dos grupos (nay_lista_de_imoveis, 07h e 19h) já pula quem está fora do mercado: o 9026 e o 9037 pararam de
-- sair no dia em que viraram Alugado. Os que continuavam saindo estavam com a situação errada no cadastro:
--   5609 (Reserva das Flores, aluguel R$ 5.800): o dono Paulo está com inquilino; em 05/10 pediu "seria melhor não
--        anunciar por enquanto" e em 28/10 14:47 repetiu "estou com a casa alugada". Foi às listas 45 vezes em 3 dias.
--   2084 (Easy Residencial, aluguel R$ 4.500): a dona Silvia em 07/10 "no momento o apto no Easy está locado,
--        portanto não disponível"; o relatório da IA de 25/10 apontou "Disponível e em oferta, mas locado a R$ 4.500".
--        Foi posto Disponível à mão no admin em 21/10. Foi às listas 30 vezes em 3 dias.
-- Mesmo efeito do PUT do admin (status = Alugado tira do site e da Nay pelo gatilho imoveis_a_situacao_manda), com a
-- trava para a leitura diária do site antigo não desfazer, e a linha no log da situação.
-- Ficaram de fora, para a equipe decidir: 1778 (proposta de R$ 4.500 em 21/10, o dono ainda pergunta se fecha) e 293
-- (à venda, com inquilina: alugado não impede vender).

BEGIN;

INSERT INTO imovel_situacao_log (codigo, de_disponivel, para_disponivel, status_antes, status_depois, quem, comando)
SELECT i.codigo, i.disponivel, false, i.status, 'Alugado', 'Claude (pedido do Pedro, 28/10)',
       CASE i.codigo WHEN 5609 THEN 'o dono disse em 28/10 que a casa está alugada (e em 05/10 pediu para não anunciar)'
                     ELSE 'a dona disse em 07/10 que está locado; relatório da IA de 25/10' END
  FROM imoveis i WHERE i.codigo IN (5609, 2084) AND i.status = 'Disponível';

UPDATE imoveis
   SET status = 'Alugado', disponivel = false, publicado_no_site = false,
       travado = true, travado_em = now(),
       travado_motivo = 'Alugado (518): o dono disse que está alugado; saiu das listas dos grupos (Pedro, 28/10)'
 WHERE codigo IN (5609, 2084) AND status = 'Disponível';

COMMIT;
