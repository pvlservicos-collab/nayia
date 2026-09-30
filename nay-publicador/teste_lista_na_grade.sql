-- A grade guardando LISTA, e as paredes que impedem a linha meio-a-meio.
--
-- O PEDIDO (Tel, 10/09): *"preciso disparar a lista de imóveis todo dia, tem
-- essa função?"*. Não tinha -- `vagas` só sabia guardar `codigos`.
--
-- O que este teste segura são as duas coisas que só quebram em produção:
-- uma linha que é imóvel E lista ao mesmo tempo (dispararia as duas coisas ou
-- nenhuma, dependendo da ordem do `if`), e a mesma lista agendada duas vezes
-- no mesmo horário -- que mandaria a lista duas vezes por dia, para sempre,
-- sem ninguém notar.
--
--   docker cp teste_lista_na_grade.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- A LINHA DE BASE, tirada ANTES de inserir qualquer coisa. A asserção 8 conta
-- vagas de lista, e a tabela de PRODUÇÃO tem as do Tel -- a primeira dela
-- somava aquelas junto. Contar o TOTAL só funcionava enquanto não existisse
-- nenhuma vaga de lista de verdade, e em 10/09 ele criou a primeira
-- (apartamento/locação/parceiros às 07:00): daí em diante o teste acusava
-- "5" onde esperava "4", sem nada estar errado.
--
-- A asserção irmã (a da vaga de imóvel) já tinha aprendido isso e se limita
-- ao que ela mesma inseriu; esta ficou de fora do conserto. Medir a DIFERENÇA
-- é imune ao que a produção guardar depois -- limitar por horário voltaria a
-- quebrar no dia em que ele agendar uma lista às 09h.
CREATE TEMP TABLE base AS
SELECT count(*) AS listas_antes FROM vagas WHERE categoria IS NOT NULL;

CREATE OR REPLACE FUNCTION pg_temp.tenta(p_sql text) RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN 'aceitou';
EXCEPTION WHEN OTHERS THEN
  RETURN 'recusou';
END $$;

-- 1. Vaga de IMÓVEL continua entrando como sempre.
INSERT INTO resultado VALUES ('vaga de imóvel entra', pg_temp.tenta($q$
  INSERT INTO vagas (horario, tipo_recorrencia, codigos)
  VALUES ('14:00', 'diaria', ARRAY['5750'])$q$), 'aceitou');

-- 2. Vaga de LISTA entra sem código.
INSERT INTO resultado VALUES ('vaga de lista entra sem código', pg_temp.tenta($q$
  INSERT INTO vagas (horario, tipo_recorrencia, codigos, categoria, negocio, destino)
  VALUES ('09:00', 'diaria', '{}', 'apartamento', 'locacao', 'parceiros')$q$),
  'aceitou');

-- 3. METADE E METADE É RECUSADO. Uma linha com código E categoria dispararia
--    as duas coisas, ou nenhuma, conforme a ordem do `if` no Python.
INSERT INTO resultado VALUES ('código + categoria é recusado', pg_temp.tenta($q$
  INSERT INTO vagas (horario, tipo_recorrencia, codigos, categoria, negocio, destino)
  VALUES ('10:00', 'diaria', ARRAY['5750'], 'apartamento', 'locacao', 'parceiros')$q$),
  'recusou');

INSERT INTO resultado VALUES ('categoria sem negócio é recusada', pg_temp.tenta($q$
  INSERT INTO vagas (horario, tipo_recorrencia, codigos, categoria)
  VALUES ('10:30', 'diaria', '{}', 'apartamento')$q$), 'recusou');

INSERT INTO resultado VALUES ('negócio sem categoria é recusado', pg_temp.tenta($q$
  INSERT INTO vagas (horario, tipo_recorrencia, codigos, negocio, destino)
  VALUES ('10:45', 'diaria', '{}', 'locacao', 'parceiros')$q$), 'recusou');

-- 4. A MESMA LISTA NO MESMO HORÁRIO SÓ ENTRA UMA VEZ. Ele repetiria o comando
--    achando que o primeiro não pegou.
INSERT INTO resultado VALUES ('a mesma lista no mesmo horário não duplica',
  pg_temp.tenta($q$
  INSERT INTO vagas (horario, tipo_recorrencia, codigos, categoria, negocio, destino)
  VALUES ('09:00', 'diaria', '{}', 'apartamento', 'locacao', 'parceiros')$q$),
  'recusou');

-- 5. Mas em OUTRO horário entra: manhã e tarde é uso legítimo.
INSERT INTO resultado VALUES ('a mesma lista em outro horário entra',
  pg_temp.tenta($q$
  INSERT INTO vagas (horario, tipo_recorrencia, codigos, categoria, negocio, destino)
  VALUES ('16:00', 'diaria', '{}', 'apartamento', 'locacao', 'parceiros')$q$),
  'aceitou');

-- 6. E para OUTRO destino também: nos grupos e no Easy são coisas diferentes.
INSERT INTO resultado VALUES ('a mesma lista no Easy entra', pg_temp.tenta($q$
  INSERT INTO vagas (horario, tipo_recorrencia, codigos, categoria, negocio, destino)
  VALUES ('09:00', 'diaria', '{}', 'apartamento', 'locacao', 'easy')$q$),
  'aceitou');

-- 7. Semanal em dias diferentes convive com a diária do mesmo horário.
INSERT INTO resultado VALUES ('semanal no mesmo horário entra', pg_temp.tenta($q$
  INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, codigos,
                     categoria, negocio, destino)
  VALUES ('09:00', 'semanal', ARRAY[2,4], '{}', 'apartamento', 'locacao', 'parceiros')$q$),
  'aceitou');

-- 8. O que entrou de verdade. Conta só o que ESTE teste inseriu: a tabela de
--    produção já tem vagas de imóvel às 14h, e a primeira versão desta
--    asserção contou aquelas junto e acusou "3 imóvel" onde eu esperava 1.
--    A de LISTA repetiu o mesmo erro e quebrou em 10/09, quando o Tel criou a
--    primeira vaga de lista de verdade -- por isso agora ela mede a diferença
--    contra a `base`, colhida no começo.
INSERT INTO resultado
SELECT 'entraram as 4 vagas de lista',
       ((SELECT count(*) FROM vagas WHERE categoria IS NOT NULL)
        - (SELECT listas_antes FROM base))::text, '4';

INSERT INTO resultado
SELECT 'e a vaga de imóvel do teste',
       (SELECT count(*)::text FROM vagas
         WHERE codigos = ARRAY['5750'] AND horario = '14:00'), '1';

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
