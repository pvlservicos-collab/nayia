# privado.condominio_ficha_antes_345  (tabela, ~0 linhas)

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

## índices
CREATE UNIQUE INDEX condominio_ficha_antes_345_condominio_id_key ON privado.condominio_ficha_antes_345 USING btree (condominio_id)
CREATE UNIQUE INDEX condominio_ficha_antes_345_nome_key ON privado.condominio_ficha_antes_345 USING btree (nome)
CREATE UNIQUE INDEX condominio_ficha_antes_345_pkey ON privado.condominio_ficha_antes_345 USING btree (id)

## restrições
condominio_ficha_antes_345_condominio_id_key: UNIQUE (condominio_id)
condominio_ficha_antes_345_nome_key: UNIQUE (nome)
condominio_ficha_antes_345_pkey: PRIMARY KEY (id)
condominio_ficha_tipo_check: CHECK ((tipo = ANY (ARRAY['apartamentos'::text, 'casas_lotes'::text])))

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
