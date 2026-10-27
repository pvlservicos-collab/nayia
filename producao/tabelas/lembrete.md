# lembrete  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('lembrete_id_seq'::regclass)
telefone  text  NOT NULL
codigo  text
referencia  text
estado  text  NOT NULL  padrão 'agendado'::text
disparar_em  timestamp with time zone  NOT NULL
tentativa  smallint  NOT NULL  padrão 0
expressao  text
regra_aplicada  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
motivo_fim  text

## índices
CREATE INDEX lembrete_agenda ON public.lembrete USING btree (disparar_em) WHERE (estado = 'agendado'::text)
CREATE UNIQUE INDEX lembrete_pkey ON public.lembrete USING btree (id)
CREATE UNIQUE INDEX lembrete_um_vivo ON public.lembrete USING btree (telefone, COALESCE(codigo, ''::text)) WHERE (estado = ANY (ARRAY['agendado'::text, 'enviado'::text, 'congelado'::text]))

## restrições
lembrete_estado_ok: CHECK ((estado = ANY (ARRAY['agendado'::text, 'enviado'::text, 'congelado'::text, 'morto'::text, 'escalado'::text])))
lembrete_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_congelar_lembretes, nay_guardar_retorno, nay_proximo_toque, nay_reservar_lembretes

## funções que citam
captacao_so_proprietario, crm_olx_bot_receber, crm_visita_agendar, crm_visita_mudar_horario, nai_abrir_turno, nai_agenda_tick, nai_cancelar_visita, nai_comando_lembrete, nai_comando_tel, nai_e_pedido_lembrete, nai_lembretes_disparar, nai_ler_lembrete, nai_liberar_saida, nai_saida_validar, nay_congelar_lembretes, nay_guardar_retorno, nay_lembretes_devidos, nay_proximo_toque, nay_reservar_lembretes, site_lembrete_criar
