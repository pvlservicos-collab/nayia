-- Chave geral do atendimento: pausa a Nay para os corretores sem
-- desmontar nada.
--
-- POR QUE NÃO BASTA DESAPROVAR OS CORRETORES: o porteiro de 29/08 manda
-- uma cortesia ("sou a assistente da Imob Easy para corretores
-- parceiros") na primeira mensagem de quem não está aprovado. Se a pausa
-- fosse feita desaprovando todo mundo, os 1.050 receberiam essa frase --
-- pior que o silêncio, porque sugere que eles não são parceiros.
--
-- POR QUE NÃO DESATIVAR O FLUXO NO n8n: o webhook pararia de responder e
-- as mensagens que chegassem durante a pausa seriam PERDIDAS, não
-- gravadas. Assim elas continuam entrando em `mensagens`, e o Tel pode
-- responder depois quem escreveu enquanto estava pausado. Os comandos
-- dele (posta, VAGAS, RESPOSTA, DESCARTAR) também continuam.
--
-- Pausar:    UPDATE config SET valor='sim' WHERE chave='atendimento_pausado';
-- Despausar: UPDATE config SET valor='nao' WHERE chave='atendimento_pausado';

CREATE TABLE IF NOT EXISTS config (
  chave        text PRIMARY KEY,
  valor        text NOT NULL,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

INSERT INTO config (chave, valor) VALUES ('atendimento_pausado', 'nao')
ON CONFLICT (chave) DO NOTHING;
