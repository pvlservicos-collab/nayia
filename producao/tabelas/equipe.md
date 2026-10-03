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
captacao_disparo_liberado, crm_parceria_com_a_rayssa, crm_parceria_marcas, crm_visita_agendar, nai_abrir_turno, nai_acompanhante, nai_agenda_tick, nai_comando_tel, nai_core_atende, nai_deve_atender, nai_e_motoboy, nai_e_proprietario_contato, nai_followup_rodar, nai_frase_visitante, nai_lembretes_disparar, nai_liberar_saida, nai_lista_governa, nai_midia_para_o_tel, nai_motoboy, nai_prosseguir_acesso, nai_saida_validar, nai_sincronizar_grupos, nai_visita_corretor_confirmou, nai_visita_para_a_rayssa, nay_e_da_equipe, site_grade_agenda, site_grade_metricas
