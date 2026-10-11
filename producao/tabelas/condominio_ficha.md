# condominio_ficha  (tabela, ~173 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('condominio_ficha_id_seq'::regclass)
condominio_id  integer
nome  text  NOT NULL
nomes_no_imovel  text[]  NOT NULL  padrão '{}'::text[]
tipo  text  NOT NULL  padrão 'apartamentos'::text
bairro  text
endereco  text
ano_lancamento  integer
construtora  text
revestimento  text
torres  text
andares  text
aptos_por_andar  text
elevador  text
unidades  text
lazer  text[]  NOT NULL  padrão '{}'::text[]
fonte  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
logradouro  text
numero  text
cidade  text
estado  text
cep  text
seguranca  text[]  NOT NULL  padrão '{}'::text[]
comodidades  text[]  NOT NULL  padrão '{}'::text[]
taxas  jsonb  NOT NULL  padrão '[]'::jsonb   -- 344: taxa de condomínio por quartos (fixa para todos os imóveis daquele tamanho) e, quando fixo, o IPTU. O IPTU por casa fica no imóvel.
ano_construcao  text
observacao  text
complemento  text
site_antigo_id  integer
ia_sugestao  jsonb   -- 348: o que a IA sugeriu (construtora, ano, torres, andares, lazer...), para conferir e aplicar no cadastro; não é lido pela Nay.
ia_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX condominio_ficha_condominio_id_key ON public.condominio_ficha USING btree (condominio_id)
CREATE UNIQUE INDEX condominio_ficha_nome_key ON public.condominio_ficha USING btree (nome)
CREATE UNIQUE INDEX condominio_ficha_pkey ON public.condominio_ficha USING btree (id)

## restrições
condominio_ficha_condominio_id_key: UNIQUE (condominio_id)
condominio_ficha_nome_key: UNIQUE (nome)
condominio_ficha_pkey: PRIMARY KEY (id)
condominio_ficha_tipo_check: CHECK ((tipo = ANY (ARRAY['apartamentos'::text, 'casas_lotes'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
site_condominio_guardar, site_condominio_salvar

## funções que citam
crm_captacao_cadastro_opcoes, nai_cadastro_importar, site_condominio_guardar, site_condominio_salvar, site_imovel_publico
