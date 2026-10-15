-- 372 -- AS MENSAGENS DA OLX NO GRUPO DA EQUIPE
--
-- Pedro, 15/10/2026: "enquanto o suporte da olx está bloqueando a nay de conversar, quero que as mensagens que cheguem
-- da olx apareçam para nós lá no grupo".
--
-- Quem escreve no nosso anúncio da OLX vira um aviso no grupo da equipe (o mesmo do vigia do WhatsApp), pelo número da
-- Parceria. Quem manda é o serviço nay-olx (olx/grupo.py), a cada 5 s; aqui só nascem as chaves dele.
-- A contagem começa na última mensagem que já existe: o que chegou antes de hoje NÃO é despejado no grupo.
-- Desligar sem código: UPDATE privado.olx_config SET valor = 'nao' WHERE chave = 'avisar_grupo';
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO privado.olx_config (chave, valor, descricao, atualizado_por) VALUES
  ('avisar_grupo', 'sim', '372: sim = quem escreve no chat da OLX aparece no grupo da equipe no WhatsApp (pela Parceria)', '372'),
  ('grupo_silencio_s', '20', '372: segundos sem a pessoa escrever antes do aviso (mensagens seguidas vão num aviso só)', '372'),
  ('grupo_ultimo_id', (SELECT coalesce(max(id), 0)::text FROM privado.olx_chat_mensagem),
   '372: a última mensagem da OLX já avisada no grupo (o nay-olx grava sozinho)', '372')
ON CONFLICT (chave) DO NOTHING;

COMMIT;
