-- Prova que o nome da NOSSA conta nunca vira nome de corretor.
--
-- O CASO (14/09): desde 12/09 as mensagens que a Nay envia também são
-- gravadas em `mensagens`, com o `senderName` da conta que enviou -- "Nay
-- Mendes". O `Gravar na fila` chama `nay_sincronizar_nome` para toda mensagem,
-- sem olhar a direção, e cada card que a Nay mandava renomeava o corretor.
-- Medido: 8 corretores viraram "Nay Mendes", entre eles a Renata, a Marlúcia
-- e a Amanda das visitas. A frase de cortesia do envio sairia "Nay, segue as
-- opções que fiquei de te enviar".
--
-- E o preenchimento de `nome_do_whatsapp.sql`, que roda de novo a cada
-- `psql -f`, pegava o nome mais recente SEM olhar a direção: rodar o arquivo
-- renomeava todo corretor que já tinha recebido mensagem dela.
--
--   docker cp teste_nome_da_conta.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

INSERT INTO config (chave, valor) VALUES ('nome_da_conta_whatsapp', 'Nay Mendes')
  ON CONFLICT (chave) DO NOTHING;

INSERT INTO corretores (telefone, nome, aprovado, ativo, nome_origem)
VALUES ('559200000001', 'Corretora Teste', true, true, 'whatsapp'),
       ('559200000002', 'Nome do Tel', true, true, 'manual');

-- 1. o nome da conta NÃO pisa no do corretor
SELECT nay_sincronizar_nome('559200000001', 'Nay Mendes');
INSERT INTO resultado
SELECT 'nome da conta é ignorado', nome, 'Corretora Teste'
  FROM corretores WHERE telefone = '559200000001';

-- 2. nem com maiúscula ou espaço diferente
SELECT nay_sincronizar_nome('559200000001', '  nay mendes ');
INSERT INTO resultado
SELECT 'nem com caixa e espaço diferentes', nome, 'Corretora Teste'
  FROM corretores WHERE telefone = '559200000001';

-- 3. o nome de verdade continua sincronizando -- a parede não pode matar o
--    motivo da função existir (o Ênio sem nome, 31/08)
SELECT nay_sincronizar_nome('559200000001', 'Corretora Teste Silva');
INSERT INTO resultado
SELECT 'nome de verdade ainda sincroniza', nome, 'Corretora Teste Silva'
  FROM corretores WHERE telefone = '559200000001';

-- 4. e o manual continua intocável
SELECT nay_sincronizar_nome('559200000002', 'Outro Nome');
INSERT INTO resultado
SELECT 'nome manual não muda', nome, 'Nome do Tel'
  FROM corretores WHERE telefone = '559200000002';

-- 5. A ASSERÇÃO QUE PEGA REGRESSÃO SOZINHA: nenhum corretor do cadastro tem o
--    nome da nossa conta.
INSERT INTO resultado
SELECT 'nenhum corretor se chama como a conta',
       CASE WHEN count(*) = 0 THEN 'nenhum' ELSE count(*) || ' corretores' END,
       'nenhum'
  FROM corretores
 WHERE lower(btrim(nome)) = lower((SELECT valor FROM config
                                    WHERE chave = 'nome_da_conta_whatsapp'));

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
