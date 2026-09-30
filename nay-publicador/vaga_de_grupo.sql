-- A GRADE PASSA A GUARDAR "ESTE IMÓVEL, NESTE GRUPO" (Tel, 27/09)
--
-- O PEDIDO, literal: "posta no grupo comercial o 5763 segunda, quarta e sexta
-- as 08h ... coloca várias variantes para eu pedir assim dessa forma ou outras
-- semelhantes, quero colocar dias diferentes de dia".
--
-- O QUE IMPEDIA: o CHECK `vagas_imovel_ou_lista` exigia `destino IS NULL` na
-- vaga de IMÓVEL. Destino de grupo só existia na vaga de LISTA. Por isso o
-- comando dele postava na hora e engolia o horário -- não havia onde guardar
-- "no grupo comercial".
--
-- O QUE NÃO PODE SE PERDER NO AFROUXAMENTO:
--
--   * VAGA LIVRE continua válida. As linhas 1, 3, 4 e 9 da grade de hoje têm
--     `codigos` VAZIO e nenhuma categoria -- são horários reservados sem
--     imóvel dentro. Exigir código aqui apagaria a grade dele.
--
--   * VAGA DE LISTA continua exigindo os três (categoria, negócio, destino) e
--     nenhum código. É o que impede uma linha ser as duas coisas.
--
-- E O ÍNDICE ÚNICO, pelo motivo já registrado no CLAUDE.md para a lista: "ele
-- repetiria o comando achando que não pegou, e os grupos receberiam duas
-- vezes por dia para sempre". Isso NÃO é hipótese -- as vagas 489 e 490 são o
-- mesmo 5749, mesmo horário, mesmos dias, duplicado exatamente assim.
--
-- O índice cobre SÓ a vaga nova (a que tem destino). Não toco nas antigas: a
-- 489/490 é decisão do Tel, não minha, e um índice que falha ao ser criado
-- deixaria esta migração pela metade.

BEGIN;

ALTER TABLE vagas DROP CONSTRAINT IF EXISTS vagas_imovel_ou_lista;

ALTER TABLE vagas ADD CONSTRAINT vagas_imovel_ou_lista CHECK (
    -- vaga de IMÓVEL (ou vaga livre): sem categoria e sem negócio.
    -- `destino` é OPCIONAL aqui -- é a mudança de 27/09.
    (categoria IS NULL AND negocio IS NULL)
    OR
    -- vaga de LISTA: os três presentes, nenhum código.
    (categoria IS NOT NULL AND negocio IS NOT NULL AND destino IS NOT NULL
     AND coalesce(array_length(codigos, 1), 0) = 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS vagas_imovel_no_grupo_unica
    ON vagas (codigos, destino, horario, tipo_recorrencia,
              coalesce(dias_semana, '{}'::integer[]))
 WHERE categoria IS NULL AND destino IS NOT NULL;

COMMIT;
