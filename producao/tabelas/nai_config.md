# nai_config  (tabela, ~71 linhas)

## colunas
chave  text  NOT NULL
valor  text  NOT NULL
descricao  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_config_pkey ON public.nai_config USING btree (chave)

## restrições
nai_config_pkey: PRIMARY KEY (chave)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_nai: SELECT
nay_site_nai, só nestas colunas: UPDATE(valor)

## funções que escrevem aqui
nai_agenda_tick, nai_comando_tel, nai_desligar_regra_publico, nai_ligar_regra_publico, nai_sincronizar_grupos

## funções que citam
nai_agenda_tick, nai_cfg, nai_checklist_texto, nai_comando_tel, nai_conferir_resposta, nai_desligar_regra_publico, nai_ligar_regra_publico, nai_sincronizar_grupos, nay_negocio_pedido
