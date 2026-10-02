# nai_retomada_resumo  (tabela, ~120 linhas)

## colunas
contato_id  bigint  NOT NULL
etapa  text  NOT NULL
resumo  text
proximo_passo  text
imoveis  integer[]  NOT NULL  padrão '{}'::integer[]
criado_em  timestamp with time zone  NOT NULL  padrão now()
valido_ate  timestamp with time zone  NOT NULL  padrão (now() + '3 days'::interval)

## índices
CREATE UNIQUE INDEX nai_retomada_resumo_pkey ON public.nai_retomada_resumo USING btree (contato_id)

## restrições
nai_retomada_resumo_contato_id_fkey: FOREIGN KEY (contato_id) REFERENCES nai_contato(id)
nai_retomada_resumo_pkey: PRIMARY KEY (contato_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_parceria_retomada, nai_retomada_texto
