# proprietarios  (tabela, ~5658 linhas)

## colunas
id  integer  NOT NULL
nome  text
telefone  text
email  text
tratamento  text
documento  text

## índices
CREATE UNIQUE INDEX proprietarios_pkey ON public.proprietarios USING btree (id)

## restrições
proprietarios_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_escrita, só nestas colunas: INSERT(id, nome, telefone, email, tratamento, documento); UPDATE(nome, telefone, email, tratamento, documento)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_captacao_cadastro_opcoes, crm_captacao_dono_cadastro, crm_etapa_da_nay, crm_etapa_manual, crm_imovel_candidatos, crm_imovel_para_cadastro, crm_parceria_marcas, nai_cadastro_pendente, nai_com_a_rayssa, nai_e_proprietario_contato, nai_liberar_saida, nai_proprietario_do_imovel
