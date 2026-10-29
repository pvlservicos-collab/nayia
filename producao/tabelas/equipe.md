# equipe  (tabela, ~0 linhas)

## colunas
telefone  text  NOT NULL
nome  text  NOT NULL
papel  text  NOT NULL
cpf  text
ativo  boolean  NOT NULL  padrão true
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX equipe_pkey ON public.equipe USING btree (telefone)

## restrições
equipe_pkey: PRIMARY KEY (telefone)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
busca_nossos_numeros, captacao_disparo_liberado, captacao_mensagem_do_python, core_saida_grupo_no_crm, crm_busca_cliente_acao, crm_busca_cliente_manual, crm_captacao_corretores, crm_parceria_com_a_rayssa, crm_parceria_marcas, crm_visita_agendar, crm_visita_leads_realizada, crm_visitas, nai_abrir_turno, nai_acompanhante, nai_agenda_tick, nai_comando_tel, nai_core_atende, nai_deve_atender, nai_e_motoboy, nai_e_proprietario_contato, nai_enviar_imoveis_para, nai_followup_rodar, nai_frase_visitante, nai_lembretes_disparar, nai_liberar_saida, nai_lista_governa, nai_midia_para_o_tel, nai_motoboy, nai_prosseguir_acesso, nai_saida_validar, nai_sincronizar_grupos, nai_turno_dono_respondeu, nai_visita_avisar_acompanhante, nai_visita_corretor_confirmou, nai_visita_para_a_rayssa, nay_e_da_equipe, olx_nay_fila, olx_nay_lead_whatsapp, site_grade_agenda, site_grade_metricas, site_painel_internos, site_painel_metricas, visita_card
