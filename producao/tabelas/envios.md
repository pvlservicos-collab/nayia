# envios  (tabela, ~5098 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('envios_id_seq'::regclass)
codigo  text
telefone  text
destino  text
grupo_nome  text
valor_enviado  numeric(14,2)
enviado_em  timestamp with time zone  padrão now()
message_id  text

## índices
CREATE INDEX envios_message_id ON public.envios USING btree (message_id) WHERE (message_id IS NOT NULL)
CREATE INDEX idx_envios_dedupe ON public.envios USING btree (telefone, codigo)
CREATE UNIQUE INDEX envios_pkey ON public.envios USING btree (id)

## restrições
envios_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
nai_confirmar_envio, nai_whatsapp_reenviado

## funções que citam
cnm_envio_lista, crm_contato_historico, crm_imoveis_enviados, crm_mensagem_citada, crm_olx_bot_receber, crm_quem_mandou, mensagens_uma_vez_so, nai_confirmar_envio, nai_contexto_corretor, nai_imoveis_na_frente, nai_imovel_da_conversa, nai_oferta_serve, nai_resposta_da_base, nai_saida_validar, nai_tel_assumiu, nai_whatsapp_reenviado, nay_codigo_confirmado, nay_codigos_da_conversa, nay_falou_conosco_atualizar, nay_ficou_devendo, nay_imovel_da_citacao, nay_imovel_do_disparo, nay_o_que_ficou_de_enviar, nay_qual_imovel, site_blog_newsletter_lista, site_grade_agenda, site_grade_metricas, site_painel_metricas
