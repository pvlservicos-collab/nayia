# imovel_lugar  (tabela, ~5674 linhas)
229 (30/09): zona, conjuntos e avenidas de cada imóvel; nai_relacionar_imovel_lugar() refaz

## colunas
codigo  integer  NOT NULL
bairro  text
zona  text
conjuntos  text[]  NOT NULL  padrão '{}'::text[]
conjuntos_do_bairro  text[]  NOT NULL  padrão '{}'::text[]
avenidas  text[]  NOT NULL  padrão '{}'::text[]
avenidas_do_bairro  text[]  NOT NULL  padrão '{}'::text[]
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX imovel_lugar_avenidas ON public.imovel_lugar USING gin (avenidas)
CREATE INDEX imovel_lugar_conjuntos ON public.imovel_lugar USING gin (conjuntos)
CREATE INDEX imovel_lugar_zona ON public.imovel_lugar USING btree (zona)
CREATE UNIQUE INDEX imovel_lugar_pkey ON public.imovel_lugar USING btree (codigo)

## restrições
imovel_lugar_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
nai_relacionar_imovel_lugar

## funções que citam
nai_disparo_buscar, nai_imovel_lugar_gatilho, nai_imovel_lugar_tudo_gatilho, nai_relacionar_imovel_lugar
