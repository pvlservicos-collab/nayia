# olx_captar  (tabela, ~0 linhas)

## colunas
olx_id  bigint  NOT NULL
url  text  NOT NULL
titulo  text
preco  numeric
preco_texto  text
tipo_negocio  text
categoria  text
bairro  text
quartos  integer
area_m2  numeric
foto  text
n_fotos  integer
anunciante  text
anunciante_id  text
telefone  text
telefones  text[]  NOT NULL  padrão '{}'::text[]
telefone_mascarado  text
whatsapp  boolean
descricao  text
publicado_em  timestamp with time zone
nota  integer  NOT NULL  padrão 0
sinais  text[]  NOT NULL  padrão '{}'::text[]
fora  text
carregado_em  timestamp with time zone  NOT NULL  padrão now()
chamado_em  timestamp with time zone
chamado_por  text
chamado_como  text

## índices
CREATE INDEX olx_captar_fora_idx ON public.olx_captar USING btree (fora) WHERE (fora IS NULL)
CREATE UNIQUE INDEX olx_captar_pkey ON public.olx_captar USING btree (olx_id)

## restrições
olx_captar_chamado_como_check: CHECK ((chamado_como = ANY (ARRAY['whatsapp'::text, 'olx'::text])))
olx_captar_pkey: PRIMARY KEY (olx_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
crm_olx_captar_chamado

## funções que citam
crm_olx_captar, crm_olx_captar_chamado
