# condominio_proximo  (tabela, ~338 linhas)
433: a planilha condominios_proximos.xlsx do Pedro (20/10): os condomínios próximos de cada um e se é recente (últimos 5 anos).

## colunas
id  integer  NOT NULL  padrão nextval('condominio_proximo_id_seq'::regclass)
nome  text  NOT NULL
bairro  text
recente  boolean  NOT NULL  padrão false
proximos  text[]  NOT NULL  padrão '{}'::text[]
condo_id  integer
ligado_como  text
carregado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX condominio_proximo_nome_key ON public.condominio_proximo USING btree (nome)
CREATE UNIQUE INDEX condominio_proximo_pkey ON public.condominio_proximo USING btree (id)

## restrições
condominio_proximo_condo_id_fkey: FOREIGN KEY (condo_id) REFERENCES condominios(id)
condominio_proximo_nome_key: UNIQUE (nome)
condominio_proximo_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
olx_cliente_buscar
