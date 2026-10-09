-- 325 -- O contrato de locação dito como começo + duração
--
-- Pedro, 09/10/2026 (conversa do Sr. Camilo, final 8900): "quando o proprietário disser que foi contratado em uma
-- data ela não pergunta até quando vai e sim quanto tempo é a duração do contrato, tipo 12 meses, 36 meses, 24 meses".
--
-- Ele disse "foi alugado em fevereiro" e a Nay perguntou "E até quando vai o contrato de locação?" -- a pergunta que
-- a ferramenta guardar_situacao do fluxo manda fazer quando falta o prazo. Quem sabe quando alugou costuma saber de
-- quanto tempo é o contrato, e não o mês em que ele acaba.
--
-- A regra mora no serviço em Python (nay-captacao/captacao/contrato.py): guardar_situacao ganhou os campos `inicio`
-- e `duracao`; com um deles a pergunta vira "E o contrato é de quanto tempo: 12, 24 ou 36 meses?" (ou "começou em que
-- mês e ano?"), e com os dois o serviço faz a conta e entrega o fim ao fluxo como `prazo`, escrito do jeito que
-- captacao_data_do_contrato (321) já transforma em data: "fevereiro de 2028 (começou em fev/2026, 24 meses)".
--
-- Aqui fica só a memória entre uma mensagem e outra: o começo vem numa, a duração na seguinte.
-- Vale para quem a Nay em Python atende (número oficial). O fluxo do n8n (Z-API) não muda.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.captacao_contrato_dito (
  lead_id        bigint PRIMARY KEY REFERENCES captacao_leads(id) ON DELETE CASCADE,
  inicio         text,
  duracao        text,
  atualizado_em  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.captacao_contrato_dito IS
  '325: quando o contrato de locação começou e de quanto tempo é, nas palavras do proprietário. O serviço nay-captacao junta os dois e calcula o fim (captacao_leads.contrato_ate).';
GRANT SELECT ON public.captacao_contrato_dito TO nay_leitura;

COMMIT;
