-- Prova o CHECK afrouxado e o índice único que impede vaga de imóvel repetida.
-- Roda dentro de uma transação que dá ROLLBACK: não suja a grade.
BEGIN;

CREATE TEMP TABLE resultado (caso text, passou boolean);

-- 1. O QUE PASSOU A SER PERMITIDO: imóvel + destino de grupo.
INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, codigos, destino)
VALUES ('08:00', 'semanal', ARRAY[1,3,5], ARRAY['5763'], 'comercial');
INSERT INTO resultado VALUES ('vaga de imóvel com destino de grupo', true);

-- 2. VAGA LIVRE continua valendo -- são 4 na grade de hoje.
INSERT INTO vagas (horario, tipo_recorrencia, codigos)
VALUES ('08:00', 'diaria', '{}');
INSERT INTO resultado VALUES ('vaga livre (sem código, sem destino)', true);

-- 3. VAGA DE IMÓVEL SEM DESTINO continua valendo (os grupos de sempre).
INSERT INTO vagas (horario, tipo_recorrencia, codigos)
VALUES ('09:00', 'diaria', ARRAY['3210']);
INSERT INTO resultado VALUES ('vaga de imóvel sem destino', true);

-- 4. VAGA DE LISTA continua exigindo os três e nenhum código.
INSERT INTO vagas (horario, tipo_recorrencia, categoria, negocio, destino, codigos)
VALUES ('10:00', 'diaria', 'sala', 'locacao', 'comercial', '{}');
INSERT INTO resultado VALUES ('vaga de lista completa', true);

-- 5. LISTA COM CÓDIGO DENTRO continua proibida -- uma linha não pode ser as duas.
DO $$ BEGIN
    INSERT INTO vagas (horario, tipo_recorrencia, categoria, negocio, destino, codigos)
    VALUES ('11:00', 'diaria', 'sala', 'locacao', 'comercial', ARRAY['5763']);
    INSERT INTO resultado VALUES ('lista com código é recusada', false);
EXCEPTION WHEN check_violation THEN
    INSERT INTO resultado VALUES ('lista com código é recusada', true);
END $$;

-- 6. LISTA SEM DESTINO continua proibida.
DO $$ BEGIN
    INSERT INTO vagas (horario, tipo_recorrencia, categoria, negocio, codigos)
    VALUES ('12:00', 'diaria', 'sala', 'locacao', '{}');
    INSERT INTO resultado VALUES ('lista sem destino é recusada', false);
EXCEPTION WHEN check_violation THEN
    INSERT INTO resultado VALUES ('lista sem destino é recusada', true);
END $$;

-- 7. O ÍNDICE ÚNICO: a MESMA vaga de grupo duas vezes não entra. É o caso
--    real das vagas 489/490 (o 5749 duplicado), que teria acontecido de novo.
DO $$ BEGIN
    INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, codigos, destino)
    VALUES ('08:00', 'semanal', ARRAY[1,3,5], ARRAY['5763'], 'comercial');
    INSERT INTO resultado VALUES ('vaga de grupo repetida é recusada', false);
EXCEPTION WHEN unique_violation THEN
    INSERT INTO resultado VALUES ('vaga de grupo repetida é recusada', true);
END $$;

-- 8. MAS O MESMO IMÓVEL EM OUTRO GRUPO é legítimo -- ele pode querer nos dois.
INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, codigos, destino)
VALUES ('08:00', 'semanal', ARRAY[1,3,5], ARRAY['5763'], 'easy');
INSERT INTO resultado VALUES ('mesmo imóvel em outro grupo entra', true);

-- 9. E EM OUTRO HORÁRIO também.
INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, codigos, destino)
VALUES ('18:00', 'semanal', ARRAY[1,3,5], ARRAY['5763'], 'comercial');
INSERT INTO resultado VALUES ('mesmo imóvel em outro horário entra', true);

-- 10. VAGA SEM DESTINO TAMBÉM NÃO REPETE (Tel, 27/09: "se ela fizer duas
--     postagens assim já não permite isso"). Este era o caso REAL: as vagas
--     489 e 490, o mesmo 5749 nos mesmos dias e horário, postando duas vezes
--     em produção. `coalesce(destino,'')` é o que faz isto valer -- NULL
--     nunca é igual a NULL num índice único.
INSERT INTO vagas (horario, tipo_recorrencia, codigos) VALUES ('19:00', 'diaria', ARRAY['777']);
DO $$ BEGIN
    INSERT INTO vagas (horario, tipo_recorrencia, codigos) VALUES ('19:00', 'diaria', ARRAY['777']);
    INSERT INTO resultado VALUES ('vaga sem destino repetida é recusada', false);
EXCEPTION WHEN unique_violation THEN
    INSERT INTO resultado VALUES ('vaga sem destino repetida é recusada', true);
END $$;

-- 11. O MESMO IMÓVEL EM OUTRO HORÁRIO continua entrando, com ou sem destino.
INSERT INTO vagas (horario, tipo_recorrencia, codigos) VALUES ('20:00', 'diaria', ARRAY['777']);
INSERT INTO resultado VALUES ('mesmo imóvel em outro horário, sem destino', true);

-- 12. VAGA LIVRE REPETIDA CONTINUA VALENDO. As vagas 3 e 4 são duas livres
--     às 08h -- sobra de VENDEU/ALUGOU, que tira o código e deixa a linha.
--     Elas não postam nada; bloqueá-las quebraria a grade dele sem resolver
--     problema nenhum.
INSERT INTO vagas (horario, tipo_recorrencia, codigos) VALUES ('21:00', 'diaria', '{}');
INSERT INTO vagas (horario, tipo_recorrencia, codigos) VALUES ('21:00', 'diaria', '{}');
INSERT INTO resultado VALUES ('duas vagas livres no mesmo horário entram', true);

-- 13. CONJUNTOS DIFERENTES de códigos são vagas diferentes.
INSERT INTO vagas (horario, tipo_recorrencia, codigos) VALUES ('22:00', 'diaria', ARRAY['777','888']);
INSERT INTO vagas (horario, tipo_recorrencia, codigos) VALUES ('22:00', 'diaria', ARRAY['777']);
INSERT INTO resultado VALUES ('conjuntos diferentes de códigos entram', true);

SELECT CASE WHEN bool_and(passou) THEN 'TODOS OS ' || count(*) || ' CASOS DA VAGA DE GRUPO PASSARAM'
            ELSE 'FALHOU: ' || string_agg(caso, '; ') FILTER (WHERE NOT passou) END
  FROM resultado;

DO $$ DECLARE n int; BEGIN
    SELECT count(*) INTO n FROM resultado WHERE NOT passou;
    IF n > 0 THEN RAISE EXCEPTION '% casos falharam', n; END IF;
END $$;

ROLLBACK;
