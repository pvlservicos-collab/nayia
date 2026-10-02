# nai_lugar_avenida  (tabela, ~42 linhas)

## colunas
nome  text  NOT NULL
expressao  text  NOT NULL
bairros  text[]  NOT NULL
ativo  boolean  NOT NULL  padrão true
criado_por  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_lugar_avenida_pkey ON public.nai_lugar_avenida USING btree (nome)

## restrições
nai_lugar_avenida_pkey: PRIMARY KEY (nome)
nai_lugar_avenida_regex_valida: CHECK (((''::text ~ expressao) IS NOT NULL))

## gatilhos
CREATE TRIGGER imovel_lugar_avenidas AFTER INSERT OR DELETE OR UPDATE ON public.nai_lugar_avenida FOR EACH STATEMENT EXECUTE FUNCTION nai_imovel_lugar_tudo_gatilho()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_imovel_candidatos, nai_condominio_da_pergunta, nai_lugar_citado, nai_relacionar_imovel_lugar
