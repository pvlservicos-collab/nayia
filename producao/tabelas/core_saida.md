# core_saida  (tabela, ~4303 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_saida_id_seq'::regclass)
turno_id  bigint  NOT NULL
chave_destino  text  NOT NULL
ordem  integer  NOT NULL
tipo  text  NOT NULL
texto  text
imagem_url  text
codigo  integer
motivo  text
enviar_apos  timestamp with time zone  NOT NULL  padrão now()
estado  text  NOT NULL  padrão 'simulado'::text
criado_em  timestamp with time zone  NOT NULL  padrão now()
papel_destino  text  NOT NULL  padrão 'turno'::text
bloqueio  text
message_id  text
resposta  jsonb
tentativas  integer  NOT NULL  padrão 0
enviado_em  timestamp with time zone

## índices
CREATE INDEX core_saida_destino ON public.core_saida USING btree (chave_destino, criado_em)
CREATE INDEX core_saida_fila ON public.core_saida USING btree (enviar_apos, turno_id, ordem) WHERE (estado = 'pendente'::text)
CREATE INDEX core_saida_message_id ON public.core_saida USING btree (message_id) WHERE (message_id IS NOT NULL)
CREATE INDEX core_saida_turno ON public.core_saida USING btree (turno_id, ordem)
CREATE UNIQUE INDEX core_saida_pkey ON public.core_saida USING btree (id)

## restrições
core_saida_check: CHECK ((((tipo = 'texto'::text) AND (texto IS NOT NULL)) OR ((tipo = 'imagem'::text) AND (imagem_url IS NOT NULL) AND (codigo IS NOT NULL))))
core_saida_estado_check: CHECK ((estado = ANY (ARRAY['simulado'::text, 'pendente'::text, 'enviando'::text, 'enviado'::text, 'bloqueado'::text, 'erro'::text])))
core_saida_papel_destino_check: CHECK ((papel_destino = ANY (ARRAY['turno'::text, 'tel'::text])))
core_saida_pkey: PRIMARY KEY (id)
core_saida_tipo_check: CHECK ((tipo = ANY (ARRAY['texto'::text, 'imagem'::text])))
core_saida_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES core_turno(id)

## gatilhos
CREATE TRIGGER core_saida_validar BEFORE INSERT OR UPDATE ON public.core_saida FOR EACH ROW EXECUTE FUNCTION core_saida_validar()

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_whatsapp_reenviado

## funções que citam
crm_imoveis_enviados, crm_mensagem_citada, crm_quem_mandou, nai_deve_atender, nai_imoveis_na_frente, nai_tel_assumiu, nai_whatsapp_reenviado
