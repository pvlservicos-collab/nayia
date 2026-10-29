# privado.lead_busca_imovel  (tabela, ~20 linhas)

## colunas
busca_id  bigint  NOT NULL
posicao  integer  NOT NULL
codigo  integer  NOT NULL
nota  numeric  NOT NULL
detalhe  jsonb  NOT NULL  padrão '[]'::jsonb

## índices
CREATE UNIQUE INDEX lead_busca_imovel_pkey ON privado.lead_busca_imovel USING btree (busca_id, codigo)

## restrições
lead_busca_imovel_busca_id_fkey: FOREIGN KEY (busca_id) REFERENCES privado.lead_busca(id) ON DELETE CASCADE
lead_busca_imovel_pkey: PRIMARY KEY (busca_id, codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_lead_buscas
