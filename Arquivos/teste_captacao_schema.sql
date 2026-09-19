-- As paredes do esquema da captação: o que o banco RECUSA.
--
-- POR QUE UM TESTE PARA CHECK CONSTRAINT: aqui a regra está no banco, não no
-- código -- e regra que ninguém exercita é intenção, não regra. Cada CHECK
-- abaixo existe porque um estado inválido específico causaria um erro
-- silencioso mais tarde, e o comentário diz qual.
--
-- HISTÓRIA DESTE ARQUIVO: ele testava também `nay_captacao_pendencias`, uma
-- função que decidia "o que ainda falta preencher" -- a MESMA regra que
-- `captacao_campos.o_que_falta` decide em Python. O `teste_captacao_pendencias_iguais.py`,
-- escrito para amarrar as duas, mostrou que discordavam nos SETE cenários: o
-- banco cobrava `cidade`, `fotos`, `logradouro` e `condominio_nome`; o Python
-- cobrava `banheiros` e `vagas`. Quem usa a tela é o Tel, e é a tela que
-- precisa de rótulo e ordem -- então o Python ficou como dono e a função saiu
-- do esquema. Os casos daquela regra vivem em `teste_captacao_campos.py`.
--
--   docker cp teste_captacao_schema.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- Roda um comando e devolve 'aceitou' ou 'recusou:<código do erro>'. Sem isto,
-- provar que o banco RECUSA exigiria uma transação por caso.
CREATE FUNCTION pg_temp.tentar(p_sql text) RETURNS text
LANGUAGE plpgsql AS $t$
BEGIN
  EXECUTE p_sql;
  RETURN 'aceitou';
EXCEPTION WHEN others THEN
  RETURN 'recusou:' || SQLSTATE;
END;
$t$;

-- ====================================================================
-- 1. A CHAVE DO LINK -- o mesmo anúncio escrito de muitas formas
-- ====================================================================

INSERT INTO resultado VALUES
 ('www e am sao o mesmo anuncio',
  CASE WHEN nay_chave_do_link('https://www.olx.com.br/x/casa-1526572128')
          = nay_chave_do_link('https://am.olx.com.br/x/casa-1526572128')
       THEN 'mesma chave' ELSE 'chaves diferentes' END, 'mesma chave');

-- O link compartilhado pelo WhatsApp vem com rastreio colado no fim.
INSERT INTO resultado VALUES
 ('utm colado pelo WhatsApp nao muda o anuncio',
  CASE WHEN nay_chave_do_link('https://am.olx.com.br/x/casa-1526572128?utm_source=whatsapp')
          = nay_chave_do_link('https://am.olx.com.br/x/casa-1526572128')
       THEN 'mesma chave' ELSE 'chaves diferentes' END, 'mesma chave');

-- Quando o proprietário edita o título, a OLX muda o SLUG e mantém o id.
INSERT INTO resultado VALUES
 ('slug diferente com o mesmo id e o mesmo anuncio',
  CASE WHEN nay_chave_do_link('https://am.olx.com.br/x/casa-boa-1526572128')
          = nay_chave_do_link('https://am.olx.com.br/x/casa-otima-1526572128')
       THEN 'mesma chave' ELSE 'chaves diferentes' END, 'mesma chave');

INSERT INTO resultado VALUES
 ('anuncios diferentes tem chaves diferentes',
  CASE WHEN nay_chave_do_link('https://am.olx.com.br/x/casa-1526572128')
          = nay_chave_do_link('https://am.olx.com.br/x/casa-1430685571')
       THEN 'mesma chave' ELSE 'chaves diferentes' END, 'chaves diferentes');

-- O teclado do celular manda a primeira letra em maiúscula.
INSERT INTO resultado VALUES
 ('Https maiusculo e o mesmo endereco',
  CASE WHEN nay_chave_do_link('Https://Am.OLX.com.br/x/casa-1526572128')
          = nay_chave_do_link('https://am.olx.com.br/x/casa-1526572128')
       THEN 'mesma chave' ELSE 'chaves diferentes' END, 'mesma chave');

-- Link sem id não pode virar NULL: NULL casaria com qualquer coisa.
INSERT INTO resultado VALUES
 ('link sem id vira a propria url, nao nulo',
  CASE WHEN nay_chave_do_link('https://am.olx.com.br/imoveis') IS NULL
       THEN 'virou nulo' ELSE 'tem chave' END, 'tem chave');

-- ====================================================================
-- 2. DEDUPE: colar o mesmo link duas vezes abre UM rascunho
-- ====================================================================

INSERT INTO captacoes (id, link_olx, olx_id)
VALUES (9000001, 'https://www.olx.com.br/x/casa-boa-1526572128', '1526572128');

INSERT INTO resultado VALUES
 ('acha o mesmo anuncio com host, slug e utm diferentes',
  coalesce((SELECT id::text FROM nay_captacao_do_link(
              'https://am.olx.com.br/x/casa-otima-1526572128?utm_source=whatsapp')),
           '(nao achou)'), '9000001');

INSERT INTO resultado VALUES
 ('anuncio nunca captado nao devolve nada',
  coalesce((SELECT id::text FROM nay_captacao_do_link(
              'https://am.olx.com.br/x/outra-9999999999')), '(nao achou)'),
  '(nao achou)');

-- O índice único é a parede de verdade: sem ele, dois cliques no botão de
-- captar abririam dois rascunhos e o Tel preencheria um e publicaria o outro.
INSERT INTO resultado VALUES
 ('o mesmo anuncio nao entra duas vezes',
  pg_temp.tentar($$INSERT INTO captacoes (id, link_olx, olx_id)
                   VALUES (9000002, 'https://am.olx.com.br/x/z-1526572128', '1526572128')$$),
  'recusou:23505');

-- ====================================================================
-- 3. O ESTADO DA CAPTAÇÃO tem que fazer sentido
-- ====================================================================

INSERT INTO resultado VALUES
 ('status inventado nao entra',
  pg_temp.tentar($$INSERT INTO captacoes (id, link_olx, status)
                   VALUES (9000003, 'https://am.olx.com.br/x/a-1', 'quase')$$),
  'recusou:23514');

-- "Publicado" sem o código do site é captação que ninguém acha depois: a
-- varredura traz o imóvel e não há como ligar um ao outro.
INSERT INTO resultado VALUES
 ('publicado sem o codigo do site nao entra',
  pg_temp.tentar($$INSERT INTO captacoes (id, link_olx, status)
                   VALUES (9000004, 'https://am.olx.com.br/x/b-2', 'publicado')$$),
  'recusou:23514');

-- "Deu erro" sem dizer qual é a mensagem que ninguém consegue agir em cima.
INSERT INTO resultado VALUES
 ('erro sem motivo nao entra',
  pg_temp.tentar($$INSERT INTO captacoes (id, link_olx, status)
                   VALUES (9000005, 'https://am.olx.com.br/x/c-3', 'erro')$$),
  'recusou:23514');

INSERT INTO resultado VALUES
 ('link vazio nao entra',
  pg_temp.tentar($$INSERT INTO captacoes (id, link_olx) VALUES (9000006, '')$$),
  'recusou:23514');

-- O carimbo de atualização é do gatilho, não de quem escreve: quem confia em
-- lembrar de atualizar à mão esquece.
UPDATE captacoes SET atualizado_em = '2020-01-01' WHERE id = 9000001;
UPDATE captacoes SET campos = '{"tipo":"Casa"}'::jsonb WHERE id = 9000001;
INSERT INTO resultado VALUES
 ('o gatilho carimba a atualizacao sozinho',
  CASE WHEN (SELECT atualizado_em FROM captacoes WHERE id = 9000001) > now() - interval '1 min'
       THEN 'carimbou' ELSE 'ficou parado' END, 'carimbou');

-- ====================================================================
-- 4. AS FOTOS -- onde o silêncio custa caro
-- ====================================================================

-- Ordem 0 quebraria a convenção de `imovel_fotos`, onde a capa é a ordem 1.
INSERT INTO resultado VALUES
 ('ordem zero nao entra',
  pg_temp.tentar($$INSERT INTO captacao_fotos (captacao_id, ordem, url_olx)
                   VALUES (9000001, 0, 'https://img.olx.com.br/images/1/a.jpg')$$),
  'recusou:23514');

-- Foto de zero byte "baixada com sucesso" é o mesmo silêncio do JPEG cinza de
-- 49 KB que a OLX devolve num 404, um degrau abaixo.
INSERT INTO resultado VALUES
 ('foto de zero byte nao entra',
  pg_temp.tentar($$INSERT INTO captacao_fotos (captacao_id, ordem, url_olx, baixada_em, caminho, bytes)
                   VALUES (9000001, 50, 'https://img.olx.com.br/images/1/vazia.jpg',
                           now(), '/tmp/vazia.jpg', 0)$$),
  'recusou:23514');

-- Baixada sem caminho é foto que ninguém acha na hora de subir para o site.
INSERT INTO resultado VALUES
 ('baixada sem caminho nao entra',
  pg_temp.tentar($$INSERT INTO captacao_fotos (captacao_id, ordem, url_olx, baixada_em)
                   VALUES (9000001, 51, 'https://img.olx.com.br/images/1/b.jpg', now())$$),
  'recusou:23514');

INSERT INTO captacao_fotos (captacao_id, ordem, url_olx, caminho, bytes, baixada_em, e_capa)
VALUES (9000001, 1, 'https://img.olx.com.br/images/1/c.jpg', '/tmp/c.jpg', 31919, now(), true);

INSERT INTO resultado VALUES
 ('a mesma ordem nao entra duas vezes',
  pg_temp.tentar($$INSERT INTO captacao_fotos (captacao_id, ordem, url_olx)
                   VALUES (9000001, 1, 'https://img.olx.com.br/images/1/d.jpg')$$),
  'recusou:23505');

INSERT INTO resultado VALUES
 ('a mesma foto nao entra duas vezes',
  pg_temp.tentar($$INSERT INTO captacao_fotos (captacao_id, ordem, url_olx)
                   VALUES (9000001, 2, 'https://img.olx.com.br/images/1/c.jpg')$$),
  'recusou:23505');

-- Duas capas é o card do site saindo com a foto errada.
INSERT INTO resultado VALUES
 ('duas capas no mesmo imovel nao entra',
  pg_temp.tentar($$INSERT INTO captacao_fotos (captacao_id, ordem, url_olx, caminho, bytes, baixada_em, e_capa)
                   VALUES (9000001, 3, 'https://img.olx.com.br/images/1/e.jpg',
                           '/tmp/e.jpg', 100, now(), true)$$),
  'recusou:23505');

-- ====================================================================
-- 5. CAMPO QUE NÃO EXISTE em `imoveis`
-- ====================================================================
-- O Rails descarta em silêncio o parâmetro fora do `permit`. Se um campo
-- inventado chegar até lá, o imóvel é criado sem ele e ninguém fica sabendo.

INSERT INTO resultado VALUES
 ('campo inventado e acusado',
  coalesce(array_to_string(nay_captacao_campos_desconhecidos(
    '{"tipo":"Casa","bairro":"Flores","xpto":"1"}'::jsonb), ','), '(nenhum)'),
  'xpto');

-- `NULLIF` porque a funcao devolve array VAZIO, nao NULL -- e
-- `array_to_string` de array vazio da string vazia, que o `coalesce` nao pega.
-- `caracteristicas` entra aqui de proposito: e coluna real de `imoveis` e o
-- tradutor da OLX preenche ela a partir de `re_features`.
INSERT INTO resultado VALUES
 ('campos de verdade nao sao acusados',
  coalesce(NULLIF(array_to_string(nay_captacao_campos_desconhecidos(
    '{"tipo":"Casa","bairro":"Flores","valor_venda":390000,"caracteristicas":"Area de servico"}'::jsonb), ','), ''),
    '(nenhum)'),
  '(nenhum)');

-- `anotacoes` e NOSSO: a anotacao do Tel sobre a captacao nao vai para o site,
-- e por isso nao e coluna de `imoveis`. Se a funcao acusar, a tela passa a
-- reclamar de um campo que ela mesma criou.
INSERT INTO resultado VALUES
 ('anotacao do Tel nao e acusada como campo inventado',
  coalesce(NULLIF(array_to_string(nay_captacao_campos_desconhecidos(
    '{"tipo":"Casa","anotacoes":"falar com o dono a tarde"}'::jsonb), ','), ''),
    '(nenhum)'),
  '(nenhum)');

SELECT CASE WHEN deu IS NOT DISTINCT FROM esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu IS NOT DISTINCT FROM esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu IS DISTINCT FROM esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
