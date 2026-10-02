# captacao_revisao  (tabela, ~30 linhas)
Triagem manual das conversas da captacao: grupo, o que falta e o rascunho da mensagem. Nao dispara nada.

## colunas
lead_id  bigint  NOT NULL
prioridade  text  NOT NULL
ordem  integer  NOT NULL  padrão 0
resumo  text
motivo  text
mensagem  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX captacao_revisao_pkey ON public.captacao_revisao USING btree (lead_id)

## restrições
captacao_revisao_lead_id_fkey: FOREIGN KEY (lead_id) REFERENCES captacao_leads(id) ON DELETE CASCADE
captacao_revisao_pkey: PRIMARY KEY (lead_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
