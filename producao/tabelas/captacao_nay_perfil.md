# captacao_nay_perfil  (tabela, ~0 linhas)
478: os perfis da Nay do número oficial. Um por lista (proprietarios, corretores...). O ativo está em captacao_config.nay_perfil_ativo; o de cada lead em captacao_leads.perfil_nay.

## colunas
nome  text  NOT NULL
descricao  text  NOT NULL  padrão ''::text
listas  text  NOT NULL  padrão ''::text
prompt_papel  text  NOT NULL
roteiro  text  NOT NULL
prompt_retrato  text
prompt_versao  integer
salvo_em  timestamp with time zone  NOT NULL  padrão now()
salvo_por  text

## índices
CREATE UNIQUE INDEX captacao_nay_perfil_pkey ON public.captacao_nay_perfil USING btree (nome)

## restrições
captacao_nay_perfil_nome_check: CHECK ((nome ~ '^[a-z][a-z0-9_]*$'::text))
captacao_nay_perfil_pkey: PRIMARY KEY (nome)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
captacao_nay_perfil_salvar

## funções que citam
captacao_nay_perfil_do_lead, captacao_nay_perfil_salvar, captacao_nay_perfil_trocar, captacao_nay_perfis
