# privado.lead_busca  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.lead_busca_id_seq'::regclass)
lead_id  integer  NOT NULL
telefone  text  NOT NULL
ordem  integer  NOT NULL  padrão 1
titulo  text  NOT NULL
disse  text
filtros  jsonb  NOT NULL  padrão '{}'::jsonb
situacao  text  NOT NULL
motivo  text
ja_enviados  integer[]  NOT NULL  padrão '{}'::integer[]
analisada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX lead_busca_fone8 ON privado.lead_busca USING btree ("right"(regexp_replace(telefone, '\D'::text, ''::text, 'g'::text), 8))
CREATE UNIQUE INDEX lead_busca_pkey ON privado.lead_busca USING btree (id)

## restrições
lead_busca_pkey: PRIMARY KEY (id)
lead_busca_situacao_check: CHECK ((situacao = ANY (ARRAY['com_opcoes'::text, 'sem_opcoes'::text, 'abaixo_do_minimo'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_lead_buscas
