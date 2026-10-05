-- 291 (05/10/2026, Pedro): "Cuidado, lá em captação ela mandou 2 vezes para o mesmo proprietário,
-- isso nunca pode acontecer, verifica os números para não ter duplicatas." Perguntado como
-- resolver, respondeu: "tira esses duplicatas analisando quem já recebeu".
--
-- O QUE ACONTECEU. Em 28/09 a fila foi refeita a pedido dele: 109 donos que tinham recebido a
-- mensagem de abertura em 14-17/09 e não tinham respondido com a situação voltaram para
-- `status = 'novo'`. A campanha religou em 29/09 e, como a ordem é por id, foi mandando a MESMA
-- mensagem de abertura de novo para eles: 79 donos receberam a segunda de 29/09 a 05/10 09:12.
-- Não é número repetido na lista (o telefone é único, por `telefone` e por `telefone_chave`):
-- é a mesma pessoa voltando para a fila.
--
-- QUEM SAI DA FILA (medido em 05/10 09:50, 40 pessoas):
--   26 que já receberam a abertura (ids 653 a 681) e seriam os próximos disparos;
--   14 que nunca receberam a abertura mas já receberam mensagem nossa por esse número, escrita
--      pela equipe (uma delas com 28 mensagens nossas, e o próprio número da Imob Easy). Hoje só
--      não são chamadas porque estão marcadas "com o Tel"; se a marca sair, a abertura iria.
-- Cada uma volta ao status de quem já foi chamado: 'respondendo' se já escreveu alguma vez,
-- 'enviado' se não. Nada é apagado e ninguém recebe mensagem por causa disto. Quem nunca
-- recebeu nada continua na fila (142). As abas do CRM não mudam: elas não leem o `status`.
--
-- Para desfazer: os ids saem no RETURNING abaixo; UPDATE ... SET status = 'novo' WHERE id IN (...).
BEGIN;

UPDATE captacao_leads l
   SET status = CASE WHEN EXISTS (SELECT 1 FROM captacao_mensagens m
                                   WHERE m.lead_id = l.id AND m.direcao = 'recebida')
                     THEN 'respondendo' ELSE 'enviado' END,
       atualizado_em = now()
 WHERE l.status = 'novo'
   AND EXISTS (SELECT 1 FROM captacao_mensagens m
                WHERE m.lead_id = l.id AND m.direcao = 'enviada'
                  AND coalesce(m.status, '') <> 'Falhou')
RETURNING l.id, right(l.telefone, 4) AS fim, l.status;

COMMIT;
