# captacao_leads  (tabela, ~2210 linhas)

## colunas
id  bigint  NOT NULL
telefone  text  NOT NULL
nome  text
tratamento  text
proprietario_id  integer
codigo  text
imovel_desc  text
condominio  text
bairro  text
tipo_imovel  text
lista_id  bigint
quem_importou  text
status  text  NOT NULL  padrão 'novo'::text
etapa  text  padrão 'novo'::text
tentativas  integer  NOT NULL  padrão 0
opt_out  boolean  NOT NULL  padrão false
pergunta_pendente  text
ultimo_envio_em  timestamp with time zone
respondeu_em  timestamp with time zone
situacao  text
contrato_ate  text
tem_outro_imovel  boolean  NOT NULL  padrão false
motivo_fim  text
fechado_em  timestamp with time zone
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
tratamento_manual  boolean  NOT NULL  padrão false
imoveis_prop  jsonb  NOT NULL  padrão '[]'::jsonb   -- TODOS os imoveis que este proprietario tem conosco, congelados na importacao. A campanha manda UMA mensagem por pessoa (telefone e UNIQUE), citando um imovel; sem esta coluna a IA nao saberia dos outros e trataria um imovel que ja e nosso como se fosse novidade.
telefone_chave  text  padrão nay_fone_chave(telefone)
quer_vender  boolean  NOT NULL  padrão false   -- O proprietario QUER vender (nao confundir com situacao=vendido, que e quem ja vendeu).
valor_venda_pedido  text   -- Quanto ele quer pedir na venda, nas palavras dele.
humano_assumiu_em  timestamp with time zone   -- O Tel assumiu este chat: a Nay nao responde mais aqui e o disparo/lembrete nao chamam.
humano_motivo  text
chat_lid  text
valor_locacao_pedido  text   -- Valor da locacao que o proprietario informou na campanha, nas palavras dele (Tel, 14/09).
situacao_por  text   -- Quem gravou a situacao: NULL/ia = a ferramenta do agente; rede = o gatilho de 15/09, quando a IA nao gravou.
canal  text   -- Por qual número o dono escreveu por último: oficial (8456-0874, via CRM) ou zapi (8595-6408). A Nay responde por ele. (154, 28/09)
modelo_abertura  text   -- 447: o modelo da Meta que abre a conversa deste lead. NULL = o do serviço (CAPTACAO_MODELO_ABERTURA, situacao_imovel_cadastrado_1). Só sai quando está em captacao_config.python_modelos_aprovados.
campanha  text   -- 454: o roteiro do modelo outro_imovel_04: alugado (lista 5: o contrato e o outro imóvel), vendido (lista 4) ou removido (lista 3: imóvel para vender). NULL = não é dessa campanha.

## índices
CREATE INDEX captacao_leads_chat_lid ON public.captacao_leads USING btree (chat_lid) WHERE (chat_lid IS NOT NULL)
CREATE INDEX captacao_leads_fila_idx ON public.captacao_leads USING btree (status, id) WHERE (NOT opt_out)
CREATE INDEX captacao_leads_followup_idx ON public.captacao_leads USING btree (status, ultimo_envio_em) WHERE (respondeu_em IS NULL)
CREATE INDEX captacao_leads_situacao_idx ON public.captacao_leads USING btree (situacao, atualizado_em DESC)
CREATE UNIQUE INDEX captacao_leads_fone_chave_uk ON public.captacao_leads USING btree (telefone_chave)
CREATE UNIQUE INDEX captacao_leads_pkey ON public.captacao_leads USING btree (id)
CREATE UNIQUE INDEX captacao_leads_telefone_key ON public.captacao_leads USING btree (telefone)

## restrições
captacao_lead_etapa_ok: CHECK (((etapa IS NULL) OR (etapa = ANY (ARRAY['novo'::text, 'aguardando_situacao'::text, 'aguardando_prazo'::text, 'aguardando_mes'::text, 'aguardando_valor'::text, 'aguardando_outros'::text, 'concluido'::text]))))
captacao_lead_situacao_ok: CHECK (((situacao IS NULL) OR (situacao = ANY (ARRAY['disponivel'::text, 'alugado'::text, 'vendido'::text]))))
captacao_lead_status_ok: CHECK ((status = ANY (ARRAY['novo'::text, 'reservado'::text, 'enviado'::text, 'erro'::text, 'respondendo'::text, 'concluido'::text, 'sem_whatsapp'::text])))
captacao_lead_telefone_cru: CHECK ((telefone ~ '^[0-9]{12,13}$'::text))
captacao_lead_tratamento_ok: CHECK (((tratamento IS NULL) OR (tratamento = ANY (ARRAY['Sr.'::text, 'Sra.'::text]))))
captacao_leads_pkey: PRIMARY KEY (id)
captacao_leads_telefone_key: UNIQUE (telefone)

## gatilhos
CREATE TRIGGER captacao_ja_chamado_nao_volta BEFORE UPDATE OF status ON public.captacao_leads FOR EACH ROW EXECUTE FUNCTION captacao_ja_chamado_nao_volta()
CREATE TRIGGER captacao_so_proprietario BEFORE UPDATE OF status ON public.captacao_leads FOR EACH ROW WHEN (((new.status = 'reservado'::text) AND (old.status IS DISTINCT FROM 'reservado'::text))) EXECUTE FUNCTION captacao_so_proprietario()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: DELETE, INSERT, SELECT, UPDATE
nay_site_leitura: SELECT
nay_disparo, só nestas colunas: SELECT(id, telefone_chave, humano_assumiu_em, chat_lid)

## funções que escrevem aqui
captacao_encerrar, captacao_guardar_lid_do_eco, captacao_olx_encerrar, captacao_olx_guardar, captacao_olx_novo, captacao_py_reservar_disparo, captacao_rede_da_situacao, captacao_so_proprietario, crm_captacao_etapa_manual, nai_abrir_turno

## funções que citam
busca_corretor_e, captacao_ainda_e_da_ia, captacao_aplicar_ao_cadastro, captacao_aplicar_pendentes, captacao_disparo_liberado, captacao_e_do_python, captacao_encerrar, captacao_ficha, captacao_ficha_aviso, captacao_fora_da_campanha, captacao_fotos_a_puxar, captacao_frase_outros, captacao_guardar_lid_do_eco, captacao_honorarios_frase, captacao_honorarios_guardar, captacao_honorarios_valor, captacao_indicacao_frase, captacao_indicacao_guardar, captacao_lead_por_contato, captacao_olx_da_parceria, captacao_olx_encerrar, captacao_olx_guardar, captacao_olx_novo, captacao_olx_proxima, captacao_py_disparo_motivo, captacao_py_fila_do_disparo, captacao_py_reservar_disparo, captacao_rede_da_situacao, captacao_so_proprietario, crm_captacao_disparo_oficial, crm_captacao_dono_cadastro, crm_captacao_donos, crm_captacao_etapa_manual, crm_captacao_funil, crm_captacao_imoveis_do_dono, crm_captacao_mensagens, crm_captacao_placar, crm_captacao_relatorio, crm_contato_da_mensagem, crm_parceria_marcas, crm_telefone_do_lid, imovel_mudanca_registrar, nai_abrir_turno, nai_cadastro_pendente, nai_e_proprietario_contato, nay_proprietario_bloqueio_atualizar, olx_organicos_novos, site_aprovar_imoveis, site_ficha_preparada, site_juntar_cadastro, site_origem_do_cadastro, site_painel_metricas, site_publicos_disparo
