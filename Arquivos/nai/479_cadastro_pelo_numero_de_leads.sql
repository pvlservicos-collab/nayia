-- 479 -- O cadastro pelo WhatsApp pergunta pelo MESMO número em que o corretor já está conversando
--
-- Tel, 23/10/2026 (a Ana, Riviera Francesa, imóvel 9057): "não faz sentido mandar busca do número de leads e a Nay
-- parceria mandar mensagem para o parceiro da informação restante; tem que ser a mesma Nay Leads fazer as perguntas e pegar
-- o restante das informações com o corretor que falta". Ela respondeu à busca pelo 8595 (Leads) e às 12:25 disse ali "É
-- andar alto / Oitavo"; às 12:31 o nay-cadastro perguntou pela Parceria (3618) "Em qual andar ele fica?".
-- - privado.cadastro_whats.canal: 'parceria' (a caixa da Nay, 3618, como sempre) ou 'leads' (a Z-API da captação, 8595:
--   o contato escreveu para o 8595 nos últimos 3 dias). O nay-cadastro decide quando cria a ficha ou recebe o contato.
-- - privado.cadastro_whats_entrada.fonte: de onde veio a resposta ('mensagens' = a porta da Parceria; 'captacao' =
--   captacao_mensagens, o 8595). Os ids de cada fonte são da sua tabela.
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE privado.cadastro_whats ADD COLUMN IF NOT EXISTS canal text NOT NULL DEFAULT 'parceria';
ALTER TABLE privado.cadastro_whats DROP CONSTRAINT IF EXISTS cadastro_whats_canal_ok;
ALTER TABLE privado.cadastro_whats ADD CONSTRAINT cadastro_whats_canal_ok CHECK (canal IN ('parceria', 'leads'));
COMMENT ON COLUMN privado.cadastro_whats.canal IS '479: por onde a Nay do cadastro pergunta: parceria (caixa da Nay, 3618) ou leads (Z-API da captação, 8595, quando o contato já conversava ali).';

ALTER TABLE privado.cadastro_whats_entrada ADD COLUMN IF NOT EXISTS fonte text NOT NULL DEFAULT 'mensagens';
ALTER TABLE privado.cadastro_whats_entrada DROP CONSTRAINT IF EXISTS cadastro_whats_entrada_fonte_ok;
ALTER TABLE privado.cadastro_whats_entrada ADD CONSTRAINT cadastro_whats_entrada_fonte_ok CHECK (fonte IN ('mensagens', 'captacao'));
COMMENT ON COLUMN privado.cadastro_whats_entrada.fonte IS '479: de onde vieram os ids: mensagens (a porta da Parceria) ou captacao (captacao_mensagens, o 8595).';

COMMIT;
