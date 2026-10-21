# captacao_imoveis_extra  (tabela, ~51 linhas)

## colunas
id  bigint  NOT NULL
lead_id  bigint  NOT NULL
descricao  text  NOT NULL
negocio  text  NOT NULL  padrão 'nao_informado'::text
curado  boolean  NOT NULL  padrão false
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX captacao_extra_lead_idx ON public.captacao_imoveis_extra USING btree (lead_id)
CREATE UNIQUE INDEX captacao_imoveis_extra_pkey ON public.captacao_imoveis_extra USING btree (id)

## restrições
captacao_extra_negocio_ok: CHECK ((negocio = ANY (ARRAY['venda'::text, 'locacao'::text, 'ambos'::text, 'nao_informado'::text])))
captacao_imoveis_extra_lead_id_fkey: FOREIGN KEY (lead_id) REFERENCES captacao_leads(id) ON DELETE CASCADE
captacao_imoveis_extra_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: DELETE, INSERT, SELECT, UPDATE
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
