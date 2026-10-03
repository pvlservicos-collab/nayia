# config  (tabela, ~16 linhas)

## colunas
chave  text  NOT NULL
valor  text  NOT NULL
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX config_pkey ON public.config USING btree (chave)

## restrições
config_pkey: PRIMARY KEY (chave)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura, só nestas colunas: SELECT(chave, valor)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nay_codigos_da_conversa, nay_descricao_segura, nay_entregas_devidas, nay_linha_da_taxa, nay_pede_localizacao_da_unidade, nay_pendencias_esquecidas, nay_pergunta_aberta_do_tel, nay_reservar_disparo_de_lista, nay_respostas_a_entregar, nay_sincronizar_nome
