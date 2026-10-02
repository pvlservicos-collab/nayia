# geo_bairro_vizinho  (tabela, ~576 linhas)

## colunas
bairro  text  NOT NULL
vizinho  text  NOT NULL
divisa  boolean  NOT NULL
km  numeric(6,2)  NOT NULL

## índices
CREATE UNIQUE INDEX geo_bairro_vizinho_pkey ON public.geo_bairro_vizinho USING btree (bairro, vizinho)

## restrições
geo_bairro_vizinho_bairro_fkey: FOREIGN KEY (bairro) REFERENCES geo_bairro(bairro) ON UPDATE CASCADE ON DELETE CASCADE
geo_bairro_vizinho_pkey: PRIMARY KEY (bairro, vizinho)
geo_bairro_vizinho_vizinho_fkey: FOREIGN KEY (vizinho) REFERENCES geo_bairro(bairro) ON UPDATE CASCADE ON DELETE CASCADE

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_bairros_ao_redor
