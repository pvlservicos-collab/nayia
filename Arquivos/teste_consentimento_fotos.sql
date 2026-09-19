-- O portão de fotos, contra as frases que já quebraram nos DOIS sentidos.
--
-- Este arquivo existe porque `teste_gatilho_fotos.js` virou documentação:
-- ele testava uma função `pediuFoto` que saiu do nó quando o portão virou
-- SQL. Dez casos verdes que não provavam nada sobre produção -- e foi essa
-- cegueira que deixou passar o bug do áudio por 20 suítes verdes.
--
-- As duas famílias de erro, as duas de caso real:
--   * ANDRÉ (30/08): ela ofereceu, ele disse "Por favor", e nada saiu.
--     Fechar demais quebra aqui.
--   * GUSTAVO (01/09): ele disse "não, as fotos eu já tenho" e recebeu
--     tudo de novo. Abrir demais quebra aqui.
-- E o envelope de áudio, que abria o portão para 100% dos áudios porque a
-- frase de sistema tinha a palavra "fotos" dentro.
--
--   docker cp teste_consentimento_fotos.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu boolean, esperado boolean);

-- Um telefone que não existe em `nay_memoria`: aqui ela NÃO ofereceu nada,
-- então "sim" sozinho não pode disparar envio.
INSERT INTO resultado
SELECT f.caso, nay_deve_mandar_fotos('5592900000003', f.txt), f.esp
  FROM (VALUES
   -- pedido explícito: tem que passar
   ('pediu direto',                'me manda as fotos',                        true),
   ('pediu a fachada',             'tem foto da fachada?',                     true),
   ('quer ver',                    'quero ver as fotos desse',                 true),
   ('pediu vídeo',                 'tem vídeo do imóvel?',                     true),
   -- a negação do Gustavo, e as irmãs dela
   ('CASO REAL Gustavo (áudio)',
    'não, as fotos eu já tenho, agora eu quero saber só o valor de entrada',   false),
   ('já mandou ontem',             'você já me enviou as fotos ontem, não precisa mandar de novo', false),
   ('já tenho as fotos do imóvel', 'já tenho as fotos do 2943, obrigado',       false),
   ('já recebi as imagens',        'já recebi as imagens',                     false),
   ('não precisa mandar as fotos', 'não precisa mandar as fotos',              false),
   -- a negação NÃO pode comer o pedido que vem junto
   ('negação de OUTRA coisa',      'já tenho o endereço, agora me manda as fotos', true),
   ('só as fotos, não o valor',    'não precisa do valor, só as fotos',        true),
   ('recebeu o card mas não a foto',
    'já recebi o card mas não recebi as fotos, manda por favor',               true),
   -- o que nunca foi pedido de foto
   ('fotógrafo não conta',         'vocês têm fotógrafo?',                     false),
   ('"ok" não é consentimento',    'ok',                                       false),
   ('"Por favor" sem oferta dela', 'Por favor',                                false),
   ('texto vazio',                 '',                                         false),
   -- O ENVELOPE DE ÁUDIO. Escrito por NÓS, e continha "fotos": para 100%
   -- dos áudios o portão devolvia true, qualquer que fosse o conteúdo.
   -- Depois do conserto ele nem chega aqui (vai o `textoCru`), mas se um
   -- dia voltar a chegar, tem que ser inofensivo.
   ('envelope de áudio genérico',
    '(o corretor mandou um audio. transcricao: "bom dia, qual o valor do condominio?") '
    || 'Antes de enviar qualquer material, repita em uma linha o que voce entendeu e peca confirmacao.',
    false)
  ) f(caso, txt, esp);

-- O CASO ANDRÉ: ela ofereceu na fala anterior, ele respondeu "Por favor".
-- Sem a oferta, a mesma frase não pode disparar (caso acima).
INSERT INTO nay_memoria (session_id, message)
VALUES ('5592900000004', '{"type":"ai","content":"quer que eu mande as fotos?"}'::jsonb);

INSERT INTO resultado
SELECT 'CASO REAL André: ela ofereceu, ele disse "Por favor"',
       nay_deve_mandar_fotos('5592900000004', 'Por favor'), true;

INSERT INTO resultado
SELECT 'ela ofereceu, mas ele disse "ok"',
       nay_deve_mandar_fotos('5592900000004', 'ok'), false;

SELECT CASE WHEN deu IS NOT DISTINCT FROM esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu IS NOT DISTINCT FROM esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu IS DISTINCT FROM esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
