-- 575 (Pedro, 03/11/2026: "criei um grupo de dúvidas ... quero uma Nay tirando dúvida de todos que perguntarem, com um
-- delayzinho para aguardar a mensagem de cada ... 5 segundos ... junta as mensagens e manda para a Nay, a Nay checa no
-- sistema e devolve a resposta e ainda sempre um conselho baseado no atendimento do Tel ... rápidas, pontuais e pequenas").
-- O grupo "Dúvidas Imobeasy" está no número da Parceria; as mensagens chegam em privado.grupo_conversa (o espelho do CRM).
-- A Nay das Dúvidas (nay-olx, olx/grupo_duvidas.py, systemd nay-duvidas) anota aqui cada resposta e as mensagens que ela
-- respondeu: o que já está aqui não é respondido de novo.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.duvida_grupo_resposta (
  id            bigserial PRIMARY KEY,
  grupo_id      text NOT NULL,
  remetente     text,
  remetente_nome text,
  mensagens     text[] NOT NULL,          -- os message_id de privado.grupo_conversa que ela juntou e respondeu
  pergunta      text,
  resposta      text,                     -- o que saiu no grupo (NULL: decidiu não responder, ex. "ok, obrigado")
  codigos       integer[],                -- os imóveis que ela consultou
  message_id    text,                     -- o id da resposta no WhatsApp
  erro          text,
  ms            integer,                  -- da última mensagem guardada até a resposta sair
  criado_em     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS duvida_grupo_resposta_mensagens ON privado.duvida_grupo_resposta USING gin (mensagens);
CREATE INDEX IF NOT EXISTS duvida_grupo_resposta_criado ON privado.duvida_grupo_resposta (grupo_id, criado_em DESC);
COMMENT ON TABLE privado.duvida_grupo_resposta IS
  '575: as respostas da Nay das Dúvidas no grupo "Dúvidas Imobeasy" (Parceria): cada linha junta as mensagens de uma pessoa';
COMMIT;
