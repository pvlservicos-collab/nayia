# captacao_contrato_dito  (tabela, ~0 linhas)
325: quando o contrato de locação começou e de quanto tempo é, nas palavras do proprietário. O serviço nay-captacao junta os dois e calcula o fim (captacao_leads.contrato_ate).

## colunas
lead_id  bigint  NOT NULL
inicio  text
duracao  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX captacao_contrato_dito_pkey ON public.captacao_contrato_dito USING btree (lead_id)

## restrições
captacao_contrato_dito_lead_id_fkey: FOREIGN KEY (lead_id) REFERENCES captacao_leads(id) ON DELETE CASCADE
captacao_contrato_dito_pkey: PRIMARY KEY (lead_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
