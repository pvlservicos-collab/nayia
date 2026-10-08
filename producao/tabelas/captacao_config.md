# captacao_config  (tabela, ~34 linhas)

## colunas
chave  text  NOT NULL
valor  text  NOT NULL
nota  text

## índices
CREATE UNIQUE INDEX captacao_config_pkey ON public.captacao_config USING btree (chave)

## restrições
captacao_config_pkey: PRIMARY KEY (chave)

## gatilhos
CREATE TRIGGER captacao_config_religou AFTER UPDATE ON public.captacao_config FOR EACH ROW WHEN (((new.chave = 'captacao_pausada'::text) AND (new.valor = 'nao'::text) AND (old.valor IS DISTINCT FROM new.valor))) EXECUTE FUNCTION captacao_config_religou()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: DELETE, INSERT, SELECT, UPDATE
nay_site_leitura: SELECT
nay_site_nai: SELECT
nay_site_nai, só nestas colunas: UPDATE(valor)

## funções que escrevem aqui
captacao_config_religou, captacao_desarmar, captacao_py_reservar_disparo, captacao_relatorio_da_vez

## funções que citam
captacao_aplicar_pendentes, captacao_cfg, captacao_config_religou, captacao_desarmar, captacao_desconectou, captacao_disparo_liberado, captacao_e_do_python, captacao_fora_da_campanha, captacao_py_disparo_motivo, captacao_py_reservar_disparo, captacao_relatorio_da_vez, captacao_teto_hoje, captacao_vigiar, crm_captacao_placar, crm_captacao_relatorio
