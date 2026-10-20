# condominio_ficha  (tabela, ~468 linhas)

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
campos_google  text[]  NOT NULL  padrão '{}'::text[]   -- Quais campos desta ficha vieram da pesquisa na web (ia_sugestao). SÓ PARA A TELA DO ADMIN mostrar "(Google)". NUNCA expor à IA: para a Nay o dado vem do mesmo lugar que os outros. Mantida pelo gatilho condominio_google_tg.
taxa_inclui  text[]  NOT NULL  padrão '{}'::text[]   -- 367: o que está incluso na taxa de condomínio (Segurança 24 horas, Água, Gás, Energia...). Vale para todo imóvel do condomínio; a Nay nova lê junto da taxa.

## índices
CREATE UNIQUE INDEX condominio_ficha_condominio_id_key ON public.condominio_ficha USING btree (condominio_id)
CREATE UNIQUE INDEX condominio_ficha_nome_key ON public.condominio_ficha USING btree (nome)
CREATE UNIQUE INDEX condominio_ficha_pkey ON public.condominio_ficha USING btree (id)

## restrições
condominio_ficha_condominio_id_key: UNIQUE (condominio_id)
condominio_ficha_nome_key: UNIQUE (nome)
condominio_ficha_pkey: PRIMARY KEY (id)
condominio_ficha_tipo_check: CHECK ((tipo = ANY (ARRAY['apartamentos'::text, 'casas_lotes'::text])))

## gatilhos
CREATE TRIGGER condominio_google_tg BEFORE INSERT OR UPDATE ON public.condominio_ficha FOR EACH ROW EXECUTE FUNCTION condominio_google_marcar()
CREATE TRIGGER condominio_proximo_anos_tg AFTER INSERT OR UPDATE OF ano_lancamento, ano_construcao, condominio_id ON public.condominio_ficha FOR EACH STATEMENT EXECUTE FUNCTION privado.condominio_proximo_anos_tg()
CREATE TRIGGER condominio_taxa_aos_imoveis_tg AFTER INSERT OR UPDATE ON public.condominio_ficha FOR EACH ROW EXECUTE FUNCTION condominio_taxa_aos_imoveis_tg()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
condominio_aplicar_google, site_condominio_guardar, site_condominio_salvar

## funções que citam
captacao_olx_anuncio, condominio_aplicar_google, condominio_taxa_aos_imoveis, crm_captacao_cadastro_opcoes, imoveis_taxa_do_condominio, nai_cadastro_importar, nai_condominio_do_imovel, olx_anuncio_montar, site_condominio_guardar, site_condominio_salvar, site_imovel_publico
