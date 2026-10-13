# contratos_locacao  (tabela, ~894 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('contratos_locacao_id_seq'::regclass)
codigo  text
vencimento  date
status_renovacao  text  padrão 'nao_perguntado'::text
ultima_acao  timestamp with time zone
proprietario_nome  text
proprietario_telefone  text
proprietario_email  text
proprietario_id_admin  integer

## índices
CREATE UNIQUE INDEX contratos_locacao_pkey ON public.contratos_locacao USING btree (id)

## restrições
contratos_locacao_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT
nay_site_escrita, só nestas colunas: INSERT(codigo, vencimento); SELECT(codigo, vencimento); UPDATE(vencimento)

## funções que escrevem aqui
captacao_aplicar_ao_cadastro, imovel_mudanca_trocar

## funções que citam
captacao_aplicar_ao_cadastro, imovel_mudanca_trocar, site_mudancas
