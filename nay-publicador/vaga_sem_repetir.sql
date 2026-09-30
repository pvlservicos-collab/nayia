-- UMA VAGA DE IMÓVEL NÃO PODE ENTRAR DUAS VEZES (Tel, 27/09)
--
-- O PEDIDO, literal: "a Nay está repetindo. o soberane duas vezes e no caso
-- ela não precisa fazer isso, se ela fizer duas postagens assim já não
-- permite isso foi algum erro que eu fiz, concerte isso".
--
-- O QUE ACONTECEU: as vagas 489 e 490 são o MESMO 5749 (Soberane Work), mesmo
-- horário (17h), mesmos dias (segunda, quarta e sábado). O grupo recebia o
-- imóvel DUAS VEZES em cada um desses dias -- e nada no sistema reclamava.
-- Não foi erro dele: ele mandou o comando duas vezes, provavelmente porque
-- o primeiro pareceu não ter pegado, e o banco aceitou os dois.
--
-- O CLAUDE.md já registrava exatamente este risco, mas só para a vaga de
-- LISTA: "Um índice único impede a mesma lista duas vezes no mesmo horário --
-- ele repetiria o comando achando que não pegou, e os grupos receberiam duas
-- vezes por dia para sempre". A vaga de IMÓVEL nunca ganhou a mesma proteção,
-- e aqui está o resultado, em produção, já rodando.
--
-- ESTE ÍNDICE SUBSTITUI o `vagas_imovel_no_grupo_unica` criado horas antes,
-- que só cobria a vaga COM destino de grupo. Um índice só, para a regra não
-- ter duas metades que divergem.
--
-- `coalesce(destino,'')` porque NULL nunca é igual a NULL num índice único:
-- sem isso, duas vagas sem destino (que é o caso do 5749) continuariam
-- passando -- o índice existiria e não protegeria nada.
--
-- VAGA LIVRE FICA DE FORA (`array_length > 0`). As vagas 3 e 4 são duas
-- livres no mesmo horário: sobra de VENDEU/ALUGOU, que tira o código e deixa
-- a linha. Elas não postam nada (`vaga_deve_disparar` devolve false), e
-- bloqueá-las quebraria a grade dele sem resolver problema nenhum.
--
-- LIMITE CONHECIDO, dito de propósito: a igualdade é de ARRAY, então
-- `{5750,5751}` e `{5751,5750}` são vagas diferentes para o índice. Repetir o
-- MESMO comando dá a mesma ordem, que é o caso real; inverter a ordem à mão
-- passaria. Ordenar exigiria função IMMUTABLE para o índice, e o ganho não
-- paga -- fica registrado em vez de resolvido pela metade.

BEGIN;

-- 1. A DUPLICADA SAI. Fica a mais antiga (489): a 490 é a repetição.
--    A regra "nunca apagar linha" do projeto é sobre `imoveis`; `vagas` é
--    reorganização de horário, e o próprio comando `tira` já apaga daqui.
DELETE FROM vagas a
 WHERE a.categoria IS NULL
   AND coalesce(array_length(a.codigos, 1), 0) > 0
   AND EXISTS (SELECT 1 FROM vagas b
                WHERE b.id < a.id
                  AND b.categoria IS NULL
                  AND b.codigos = a.codigos
                  AND b.destino IS NOT DISTINCT FROM a.destino
                  AND b.horario = a.horario
                  AND b.tipo_recorrencia = a.tipo_recorrencia
                  AND coalesce(b.dias_semana, '{}') = coalesce(a.dias_semana, '{}'));

-- 2. O índice geral entra no lugar do que só cobria grupo.
DROP INDEX IF EXISTS vagas_imovel_no_grupo_unica;

CREATE UNIQUE INDEX IF NOT EXISTS vagas_imovel_unica
    ON vagas (codigos, coalesce(destino, ''), horario, tipo_recorrencia,
              coalesce(dias_semana, '{}'::integer[]))
 WHERE categoria IS NULL AND coalesce(array_length(codigos, 1), 0) > 0;

COMMIT;
