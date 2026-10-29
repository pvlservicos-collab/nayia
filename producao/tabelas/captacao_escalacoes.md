# captacao_escalacoes  (tabela, ~1036 linhas)
Escaladas da CAMPANHA de captacao. Separada de pendencias de proposito: pendencias e do atendimento a corretor e alimenta o reuso de resposta da Nay; a captacao e temporaria e nao deve sujar aquele historico.

## colunas
id  bigint  NOT NULL
lead_id  bigint
telefone  text  NOT NULL
nome  text
assunto  text  NOT NULL
disse  text
resposta  text
resolvida  boolean  NOT NULL  padrão false
criada_em  timestamp with time zone  NOT NULL  padrão now()
resolvida_em  timestamp with time zone

## índices
CREATE INDEX captacao_escalacoes_abertas_idx ON public.captacao_escalacoes USING btree (resolvida, criada_em DESC)
CREATE UNIQUE INDEX captacao_escalacoes_pkey ON public.captacao_escalacoes USING btree (id)

## restrições
captacao_escalacoes_lead_id_fkey: FOREIGN KEY (lead_id) REFERENCES captacao_leads(id) ON DELETE SET NULL
captacao_escalacoes_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: INSERT, SELECT, UPDATE
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
