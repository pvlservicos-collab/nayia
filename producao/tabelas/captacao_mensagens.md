# captacao_mensagens  (tabela, ~6753 linhas)

## colunas
id  bigint  NOT NULL
lead_id  bigint
telefone  text
direcao  text  NOT NULL
origem  text
texto  text
status  text
message_id  text
criada_em  timestamp with time zone  NOT NULL  padrão now()
entregue_em  timestamp with time zone
lida_em  timestamp with time zone

## índices
CREATE INDEX captacao_mensagens_chave_idx ON public.captacao_mensagens USING btree (nay_fone_chave(telefone), direcao, status)
CREATE INDEX captacao_mensagens_dia_idx ON public.captacao_mensagens USING btree (direcao, criada_em DESC)
CREATE INDEX captacao_mensagens_fila_idx ON public.captacao_mensagens USING btree (telefone, direcao, status)
CREATE INDEX captacao_mensagens_lead_idx ON public.captacao_mensagens USING btree (lead_id, criada_em)
CREATE INDEX captacao_mensagens_message_id_idx ON public.captacao_mensagens USING btree (message_id) WHERE (message_id IS NOT NULL)
CREATE UNIQUE INDEX captacao_mensagens_pkey ON public.captacao_mensagens USING btree (id)

## restrições
captacao_mensagens_lead_id_fkey: FOREIGN KEY (lead_id) REFERENCES captacao_leads(id) ON DELETE SET NULL
captacao_mensagens_pkey: PRIMARY KEY (id)
captacao_msg_direcao_ok: CHECK ((direcao = ANY (ARRAY['enviada'::text, 'recebida'::text])))

## gatilhos
CREATE TRIGGER captacao_mensagem_do_python BEFORE INSERT ON public.captacao_mensagens FOR EACH ROW EXECUTE FUNCTION captacao_mensagem_do_python()
CREATE TRIGGER captacao_rede_da_situacao_tg AFTER INSERT ON public.captacao_mensagens FOR EACH ROW EXECUTE FUNCTION captacao_rede_da_situacao()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: DELETE, INSERT, SELECT, UPDATE
nay_site_leitura: SELECT
nay_site_escrita, só nestas colunas: SELECT(entregue_em, lida_em)

## funções que escrevem aqui
captacao_status_da_mensagem

## funções que citam
captacao_aplicar_ao_cadastro, captacao_aplicar_pendentes, captacao_disparo_liberado, captacao_encerrar, captacao_honorarios_pendente, captacao_indicacao_pendente, captacao_ja_chamado_nao_volta, captacao_ja_perguntou_outros, captacao_py_disparo_motivo, captacao_py_disparo_placar, captacao_py_fila_do_disparo, captacao_relatorio_da_vez, captacao_status_da_mensagem, captacao_vigiar, crm_captacao_disparo_oficial, crm_captacao_mensagens, crm_captacao_placar, crm_captacao_relatorio, crm_contato_da_mensagem, crm_mensagem_citada, nay_falou_conosco_atualizar, site_publicos_disparo
