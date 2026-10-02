# geo_bairro_nome  (tabela, ~45 linhas)

## colunas
nome_cadastro  text  NOT NULL
bairro  text  NOT NULL

## índices
CREATE UNIQUE INDEX geo_bairro_nome_pkey ON public.geo_bairro_nome USING btree (nome_cadastro)

## restrições
geo_bairro_nome_bairro_fkey: FOREIGN KEY (bairro) REFERENCES geo_bairro(bairro) ON UPDATE CASCADE
geo_bairro_nome_pkey: PRIMARY KEY (nome_cadastro)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
