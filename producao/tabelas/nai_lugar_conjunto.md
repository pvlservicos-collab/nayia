# nai_lugar_conjunto  (tabela, ~0 linhas)

## colunas
nome  text  NOT NULL
expressao  text  NOT NULL
bairro  text  NOT NULL
zona  text
avenidas  text
ativo  boolean  NOT NULL  padrão true
criado_por  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_lugar_conjunto_pkey ON public.nai_lugar_conjunto USING btree (nome)

## restrições
nai_lugar_conjunto_pkey: PRIMARY KEY (nome)
nai_lugar_conjunto_regex_valida: CHECK (((''::text ~ expressao) IS NOT NULL))

## gatilhos
CREATE TRIGGER imovel_lugar_conjuntos AFTER INSERT OR DELETE OR UPDATE ON public.nai_lugar_conjunto FOR EACH STATEMENT EXECUTE FUNCTION nai_imovel_lugar_tudo_gatilho()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_bairros_do_conjunto, nai_lugar_citado, nai_nome_so_do_bairro, nai_relacionar_imovel_lugar
