-- 551 (Pedro, 31/10/2026: "tire tudo do n8n quero tudo em python"). As duas tabelas da PORTA do nay-core
-- (container nay-core-porta, nay/porta/): o que chega da Z-API e do CRM entra aqui primeiro e a porta responde 200
-- na hora; o laço dela processa depois, sem prender vaga de nada.
--   core_porta_evento  o corpo cru de cada webhook, por linha (parceria | captacao | oficial | status | crm), com o
--                      modo da chave na chegada (550: n8n | sombra | python) e o que a porta fez com ele
--   core_porta_sombra  no modo sombra: o que a porta GRAVARIA (sem gravar), para comparar com o que o n8n gravou
-- Quem escreve é a porta, com o papel do .env dela (PORTA_DATABASE_URL); o painel do core só lê.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.core_porta_evento (
  id            bigserial PRIMARY KEY,
  linha         text NOT NULL CHECK (linha IN ('parceria', 'captacao', 'oficial', 'status', 'crm')),
  corpo         jsonb NOT NULL,
  message_id    text,
  modo          text NOT NULL CHECK (modo IN ('n8n', 'sombra', 'python')),
  recebido_em   timestamptz NOT NULL DEFAULT now(),
  processado_em timestamptz,
  resultado     jsonb,
  erro          text
);
-- a mesma mensagem duas vezes (a Z-API repete, "recebida" + "recebida e entregue") morre na inserção
CREATE UNIQUE INDEX IF NOT EXISTS core_porta_evento_mensagem ON public.core_porta_evento (linha, message_id)
  WHERE message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS core_porta_evento_pendente ON public.core_porta_evento (id) WHERE processado_em IS NULL;
COMMENT ON TABLE public.core_porta_evento IS '551: o que chegou na porta Python do nay-core (nay/porta), por linha';

CREATE TABLE IF NOT EXISTS public.core_porta_sombra (
  id          bigserial PRIMARY KEY,
  linha       text NOT NULL,
  evento_id   bigint REFERENCES public.core_porta_evento (id) ON DELETE CASCADE,
  message_id  text,
  telefone    text,
  direcao     text,
  origem      text,
  texto       text,
  acao        text NOT NULL,     -- gravaria_fila | tel_assumiria | eco_lid | foto_do_dono | status | desconectou
  criado_em   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS core_porta_sombra_quando ON public.core_porta_sombra (linha, criado_em);
COMMENT ON TABLE public.core_porta_sombra IS '551: no modo sombra, o que a porta gravaria; comparar com mensagens / captacao_mensagens';

GRANT SELECT ON public.core_porta_evento, public.core_porta_sombra TO nay_core, nay_leitura;

COMMIT;
