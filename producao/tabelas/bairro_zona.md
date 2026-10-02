# bairro_zona  (tabela, ~56 linhas)

## colunas
bairro  text  NOT NULL
zona  text  NOT NULL

## índices
CREATE UNIQUE INDEX bairro_zona_pkey ON public.bairro_zona USING btree (bairro)

## restrições
bairro_zona_pkey: PRIMARY KEY (bairro)

## gatilhos
CREATE TRIGGER imovel_lugar_zonas AFTER INSERT OR DELETE OR UPDATE ON public.bairro_zona FOR EACH STATEMENT EXECUTE FUNCTION nai_imovel_lugar_tudo_gatilho()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_imovel_pelo_condominio, nai_lugar_citado, nai_nome_so_do_bairro, nai_relacionar_imovel_lugar, nay_bairros_proximos
