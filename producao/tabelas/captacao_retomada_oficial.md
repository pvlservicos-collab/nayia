# captacao_retomada_oficial  (tabela, ~91 linhas)
323: leads que já receberam a abertura pela Z-API e nunca responderam; o disparo do Python (modelo oficial) pode chamá-los UMA vez. Apagar a linha tira da fila.

## colunas
lead_id  bigint  NOT NULL
motivo  text  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX captacao_retomada_oficial_pkey ON public.captacao_retomada_oficial USING btree (lead_id)

## restrições
captacao_retomada_oficial_lead_id_fkey: FOREIGN KEY (lead_id) REFERENCES captacao_leads(id) ON DELETE CASCADE
captacao_retomada_oficial_pkey: PRIMARY KEY (lead_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
captacao_py_fila_do_disparo, captacao_py_reservar_disparo, crm_captacao_disparo_oficial, site_publicos_disparo
