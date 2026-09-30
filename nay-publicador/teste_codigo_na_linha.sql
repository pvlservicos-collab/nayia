-- O CÓDIGO NA LINHA DA LISTA (Tel, 28/09) -- e o que ele conserta de quebra.
--
-- O PEDIDO era de formato: "quero com o código também". O efeito colateral é
-- o que mais importa: `nay_linha_da_lista` é a IDENTIDADE que o casamento
-- reverso regenera, e ela NÃO ERA INJETORA -- o 5719 e o 5728 rendiam a mesma
-- string, e por isso a Nay tinha de perguntar qual dos dois. Com o código
-- dentro, a ambiguidade some da origem.
--
-- Roda em transação com ROLLBACK: não escreve nada.
BEGIN;

CREATE TEMP TABLE r (caso text, passou boolean);

-- 1. O FORMATO que ele pediu: o código colado no nome, antes da primeira " / ".
INSERT INTO r
SELECT 'o código sai colado ao nome, antes da primeira barra',
       nay_linha_da_lista(c.codigo, 'apartamento', 'locacao')
         ~ ('^[^/]* cod ' || c.codigo || ' /')
  FROM nay_codigos_da_lista('apartamento','locacao') c LIMIT 1;

-- 2. NENHUMA LINHA DO CATÁLOGO É AMBÍGUA -- é a asserção que vale.
INSERT INTO r
WITH combos AS (
  SELECT c, n FROM
    (SELECT unnest(ARRAY['apartamento','apartamento_via_publica','casa_condominio',
                         'casa_via_publica','sala','lote']) c) a,
    (SELECT unnest(ARRAY['venda','locacao']) n) b),
todas AS (
  SELECT nay_linha_da_lista(k.codigo, combos.c, combos.n) AS linha
    FROM combos CROSS JOIN LATERAL nay_codigos_da_lista(combos.c, combos.n) k)
SELECT 'nenhuma linha do catálogo se repete', count(*) = count(DISTINCT linha)
  FROM todas;

-- 3. O CASO HISTÓRICO: 5719 e 5728, os dois "2 quartos sendo 1 suíte / 2.6k".
INSERT INTO r VALUES ('o 5719 e o 5728 deixaram de render a mesma string',
  (SELECT nay_linha_da_lista('5719','apartamento','locacao')
       <> nay_linha_da_lista('5728','apartamento','locacao')));

-- 4. LER DE VOLTA: a linha nova resolve pelo CÓDIGO, na faixa mais precisa.
INSERT INTO r
SELECT 'linha com cod resolve pelo código, faixa -1',
       count(*) = 1 AND min(codigo) = '5728' AND min(faixa) = -1
  FROM nay_imoveis_da_linha(nay_linha_da_lista('5728','apartamento','locacao'));

-- 5. A COLAGEM VELHA, sem código, continua casando. Ele pode colar uma lista
--    que a Nay mandou ontem -- e sem isto toda ela cairia para as faixas de
--    atributo, que são menos precisas.
INSERT INTO r
SELECT 'linha SEM cod (colagem antiga) ainda resolve',
       count(*) = 1 AND min(codigo) = '5728'
  FROM nay_imoveis_da_linha(
         nay_linha_sem_codigo(nay_linha_da_lista('5728','apartamento','locacao')));

-- 6. O VALOR MUDOU DESDE A COLAGEM e o código salva. Não é hipótese: desde
--    28/09 a lista relê os preços no site antes de sair.
INSERT INTO r
SELECT 'código resolve mesmo com o valor desatualizado',
       count(*) = 1 AND min(codigo) = '5728'
  FROM nay_imoveis_da_linha('Park Golf cod 5728 / 2 quartos sendo 1 suíte / 9.9k');

-- 7. CÓDIGO QUE NÃO EXISTE não atrapalha: cai no funil de sempre.
INSERT INTO r
SELECT 'código inexistente não impede o funil de nome',
       count(*) >= 1
  FROM nay_imoveis_da_linha(
         'Park Golf cod 99999 / 2 quartos sendo 1 suíte / semi-mobiliado / 2.6k (incluso a tx)');

-- 8. O NOME não pode levar o "cod NNNN" junto -- senão nenhuma das cinco
--    faixas de casamento de nome reconheceria o condomínio.
INSERT INTO r
SELECT 'o nome sai sem o código', nome = 'Park Golf'
  FROM nay_partes_da_linha('✅Park Golf cod 5728 / 2 quartos sendo 1 suíte / 2.6k');

-- 9. E O VALOR não pode ser o código. O código é um número solto perto do
--    começo; o valor é o último. Sem tirar o código antes, a busca pelo
--    "último token numérico" fica exposta -- é a mesma lição do "as 08:00".
INSERT INTO r
SELECT 'o valor continua sendo o valor, não o código', valor = 2600
  FROM nay_partes_da_linha('✅Park Golf cod 5728 / 2 quartos sendo 1 suíte / 2.6k');

-- 10. AS FORMAS DE ESCREVER o código que a leitura aceita. A que a lista
--     GERA é "cod NNNN"; as outras são como ele e os corretores escrevem.
INSERT INTO r
SELECT 'aceita cod / cód. / codigo: / código', bool_and(achou) FROM (
  SELECT nay_codigo_da_linha(v) = '5728' AS achou
    FROM unnest(ARRAY['Park Golf cod 5728 / 2.6k',
                      'Park Golf cód. 5728 / 2.6k',
                      'Park Golf codigo: 5728 / 2.6k',
                      'Park Golf código 5728 / 2.6k']) v) x;

-- 11. E NÃO INVENTA CÓDIGO onde não há. "2 quartos" não é código.
INSERT INTO r VALUES ('linha sem código devolve NULL',
  (SELECT nay_codigo_da_linha('Park Golf / 2 quartos sendo 1 suíte / 2.6k') IS NULL));

-- 12. O "cod" NÃO PODE virar o gatilho de fotos, que procura "Código: NNNN"
--     com dois pontos. Se casasse, cada linha da lista mandaria um álbum.
INSERT INTO r
SELECT 'o formato não dispara o gatilho de fotos',
       nay_linha_da_lista('5728','apartamento','locacao') !~ 'C[óo]digo:\s*[0-9]';

SELECT CASE WHEN bool_and(passou)
            THEN 'TODOS OS ' || count(*) || ' CASOS DO CÓDIGO NA LINHA PASSARAM'
            ELSE 'FALHOU: ' || string_agg(caso, '; ') FILTER (WHERE NOT passou) END
  FROM r;

DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM r WHERE NOT passou OR passou IS NULL;
  IF n > 0 THEN RAISE EXCEPTION '% casos falharam', n; END IF;
END $$;

ROLLBACK;
