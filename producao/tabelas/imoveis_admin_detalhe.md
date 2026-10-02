# imoveis_admin_detalhe  (tabela, ~894 linhas)

## colunas
codigo  text  NOT NULL
tipo  text
bairro  text
cidade  text
logradouro  text
numero  text
cep  text
andar  text
area  numeric
quartos  integer
suites  integer
banheiros  integer
vagas  integer
vagas_cobertas  integer
sol  text
caracteristicas  text
valor_aluguel  numeric
valor_venda  numeric
garantia  text
incluso  text
captado_em  date
financiamento  text
visitas_30d  integer
condominio_id  integer
condominio  text
coletado_em  timestamp with time zone  NOT NULL  padrão now()
bloco  text
casa  text
torre  text
apartamento  text
estado  text
terreno  numeric
area_construida  numeric
taxa_condominio  numeric
iptu  numeric
lances_escada  integer
locatario_nome  text
locatario_contato  text
observacoes  text
observacao_aluguel  text
inspecionado_por  text
vencimento  date

## índices
CREATE INDEX ix_iad_captado ON public.imoveis_admin_detalhe USING btree (captado_em)
CREATE UNIQUE INDEX imoveis_admin_detalhe_pkey ON public.imoveis_admin_detalhe USING btree (codigo)

## restrições
imoveis_admin_detalhe_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_listas: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
