-- QUEM TEM A VOZ DO TEL NÃO TEM O PRÓPRIO CHAT ASSUMIDO (Tel, 28/09)
--
-- O CASO, com hora: às 12h35 o número da Imob Easy (92 98595-6408) ganhou a
-- voz do Tel. Às 08h40 ele escreveu, a Nay entendeu "o Tel escreveu pelo
-- celular" e carimbou o chat. Às 08h41 o comando `92 8464-8446 envia o 5739`
-- chegou DESSE MESMO número e morreu em "Com o Tel" -- a marca que ele
-- acabara de criar bloqueou o comando dele.
--
-- O VENENO ESTAVA NO IRMÃO `@lid`: a marca ficou em `lid:5124097359973`, e o
-- `escala_sem_parar` -- que deveria impedir o carimbo -- compara por TELEFONE.
-- Um `@lid` nunca casa um telefone. Por isso a parede tem de estar na
-- LEITURA, que enxerga os dois lados da identidade, e não só na escrita.
--
-- Roda em transação com ROLLBACK: não mexe em conversa de ninguém.
BEGIN;

CREATE TEMP TABLE r (caso text, passou boolean);

-- Um contato de mentira com a voz do Tel, e o irmão @lid dele.
INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
VALUES ('5592985956408', '5592985956408', 'zz teste voz do tel');

-- 1. A VOZ DO TEL é reconhecida nas quatro formas que a Z-API entrega.
INSERT INTO r
SELECT 'a voz do Tel vale com e sem o 9, com e sem o 55', bool_and(v) FROM (
  SELECT nai_e_voz_do_tel(nai_chave(n)) AS v
    FROM unnest(ARRAY['559294717316','5592985956408','559285956408',
                      '9285956408','92 98595-6408']) n) x;

-- 2. E NÃO vale para quem não está na lista.
INSERT INTO r VALUES ('corretor comum não tem a voz do Tel',
  (SELECT NOT nai_e_voz_do_tel(nai_chave('559288548030'))));

-- 3. O CHAT DO TEL NÃO FICA ASSUMIDO, nem quando a marca está nele mesmo.
UPDATE nai_contato
   SET humano_assumiu_em = now(), humano_motivo = 'o Tel escreveu pelo celular'
 WHERE chave = '5592985956408';
INSERT INTO r
SELECT 'marca no próprio contato do Tel não segura',
       NOT nai_tel_com_a_conversa(id)
  FROM nai_contato WHERE chave = '5592985956408';

-- 4. NEM QUANDO A MARCA ESTÁ NO IRMÃO -- que é o caso real, porque ela ficou
--    no `@lid` e o `escala_sem_parar` compara por telefone.
UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL
 WHERE chave = '5592985956408';
INSERT INTO r
SELECT 'marca no irmão @lid também não segura',
       NOT nai_tel_com_a_conversa(id)
  FROM nai_contato WHERE chave = '5592985956408';

-- 5. E O RECURSO CONTINUA VALENDO para corretor de verdade -- é a parte que
--    não pode quebrar: o Tel escreve no chat de um corretor e a Nay recua.
INSERT INTO nai_contato (chave, telefone, nome_whatsapp,
                         humano_assumiu_em, humano_motivo)
VALUES ('5592900000001', '5592900000001', 'zz corretor de teste',
        now(), 'o Tel escreveu pelo celular');
INSERT INTO r
SELECT 'no chat de um corretor a Nay continua recuando',
       nai_tel_com_a_conversa(id)
  FROM nai_contato WHERE chave = '5592900000001';

-- 6. E a janela de 30 minutos continua expirando para ele.
UPDATE nai_contato SET humano_assumiu_em = now() - interval '10 hours'
 WHERE chave = '5592900000001';
INSERT INTO r
SELECT 'e a janela do corretor expira',
       NOT nai_tel_com_a_conversa(id)
  FROM nai_contato WHERE chave = '5592900000001';

-- 7. MOTIVO QUE NÃO É "pelo celular" não expira -- é assumir de verdade.
UPDATE nai_contato
   SET humano_assumiu_em = now() - interval '10 hours',
       humano_motivo = 'duvida fora da base'
 WHERE chave = '5592900000001';
INSERT INTO r
SELECT 'assumir de verdade não expira com o tempo',
       nai_tel_com_a_conversa(id)
  FROM nai_contato WHERE chave = '5592900000001';

SELECT CASE WHEN bool_and(passou)
            THEN 'TODOS OS ' || count(*) || ' CASOS DA VOZ DO TEL PASSARAM'
            ELSE 'FALHOU: ' || string_agg(caso, '; ') FILTER (WHERE NOT passou) END
  FROM r;

DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM r WHERE NOT passou OR passou IS NULL;
  IF n > 0 THEN RAISE EXCEPTION '% casos falharam', n; END IF;
END $$;

ROLLBACK;
