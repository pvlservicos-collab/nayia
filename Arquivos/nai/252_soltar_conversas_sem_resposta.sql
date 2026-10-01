-- 252 (01/10/2026): SOLTAR DUAS CONVERSAS QUE FICARAM SEM RESPOSTA.
-- Pedro: "tem várias mensagens de corretores que estão em todos mas ela não
-- respondeu desde de manhã... o que faltar põe para responder analisando o
-- contexto".
--
-- Medido às 13:55 de hoje: 16 corretores com a última palavra deles e sem
-- resposta há mais de 35 min. TODOS os 16 estavam calados pelo mesmo motivo --
-- a conversa tinha sido assumida por gente (o Tel escreveu pelo celular, a
-- revisão de 30/09 passou para a Rayssa, ou ela escalou uma dúvida fora da
-- base) -- e a marca não vence: ela só sai com DEVOLVER.
--
-- Destas 16, 9 são cortesia ("Ok", "obrigada", "Entendi", "Está bem"): não
-- pedem resposta. 5 pedem GENTE, não a Nay (dívida no Serasa, proprietária que
-- não sabia que era para clínica, visita em andamento com CPF já enviado).
-- Sobram duas, que são pergunta de corretor e a Nay sabe responder:
--
--   6302  André Barreto, 08:48 -- "cliente que busca aluguel até 4 mil pelo
--         Adrianópolis, naquela região onde está o Soberane. Semi-mobiliado".
--         É pedido de busca completo; calou porque o Tel escreveu 08:30.
--   8003  Luciana Viana, 10:59 -- "Temos Bosque dos Ingleses para venda?".
--         Calou porque ela escalou como dúvida fora da base. Temos resposta:
--         os dois Bosque dos Ingleses estão Vendidos, e há dois Parque dos
--         Ingleses à venda (2392 e 9004).
--
-- Soltar aqui só tira a marca. Quem faz a Nay responder AGORA é a reentrega da
-- mensagem no webhook da NAI, feita depois deste arquivo (o mesmo caminho do
-- botão verde "Nay voltar a atender").
BEGIN;
SET LOCAL lock_timeout = '3s';

SELECT c.chave, (crm_nay_voltar(c.telefone, 'Pedro (sem resposta desde a manhã)')).*
  FROM nai_contato c
 WHERE right(c.chave, 8) IN (
         SELECT DISTINCT right(regexp_replace(m.telefone, '\D', '', 'g'), 8)
           FROM mensagens m
          WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 4) IN ('6302', '8003')
            AND m.criada_em > now() - interval '30 hours')
   AND c.telefone IS NOT NULL;
COMMIT;
