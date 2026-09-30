-- A grade passa a guardar LISTA, não só imóvel.
--
-- O PEDIDO (Tel, 10/09): *"preciso disparar a lista de imóveis todo dia, tem
-- essa função?"*. Não tinha: `vagas` só sabia guardar `codigos`, e a lista só
-- saía quando ele digitava o comando na hora.
--
-- POR QUE NA MESMA TABELA, e não numa nova: a grade é UMA coisa para ele. O
-- `Nay VAGAS` mostra tudo junto, o `agendador.py` decide o que dispara agora
-- sem saber o que tem dentro, e o cron de minuto em minuto já é um só. Uma
-- segunda tabela significaria um segundo `VAGAS`, um segundo cron e um
-- segundo lugar para esquecer de olhar.
--
-- A LINHA É UMA COISA OU OUTRA, e o banco é quem garante: ou é vaga de imóvel
-- (`categoria` nula e `codigos` preenchido) ou é vaga de lista (as três
-- colunas preenchidas e `codigos` vazio). Sem esta parede, uma vaga com
-- código E categoria dispararia as duas coisas, ou nenhuma, dependendo da
-- ordem do `if` -- e isso é o tipo de coisa que só aparece em produção.
--
--   docker cp lista_na_grade.sql nay-postgres:/tmp/l.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/l.sql

ALTER TABLE vagas ADD COLUMN IF NOT EXISTS categoria text;
ALTER TABLE vagas ADD COLUMN IF NOT EXISTS negocio   text;
ALTER TABLE vagas ADD COLUMN IF NOT EXISTS destino   text;

-- `IF NOT EXISTS` não existe para constraint; o DO faz o mesmo papel e deixa
-- o arquivo idempotente, que é como todo .sql deste projeto é rodado.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'vagas_imovel_ou_lista') THEN
    ALTER TABLE vagas ADD CONSTRAINT vagas_imovel_ou_lista CHECK (
      (categoria IS NULL AND negocio IS NULL AND destino IS NULL)
      OR (categoria IS NOT NULL AND negocio IS NOT NULL AND destino IS NOT NULL
          AND coalesce(array_length(codigos, 1), 0) = 0)
    );
  END IF;
END $$;

-- A mesma lista não pode entrar duas vezes no mesmo horário: ele repetiria o
-- comando achando que o primeiro não pegou, e os grupos receberiam a lista
-- duas vezes, todo dia, sem ninguém notar.
CREATE UNIQUE INDEX IF NOT EXISTS vagas_lista_unica
  ON vagas (categoria, negocio, destino, horario,
            tipo_recorrencia, coalesce(dias_semana, '{}'::int[]))
  WHERE categoria IS NOT NULL;
