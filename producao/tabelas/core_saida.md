# core_saida  (tabela, ~250 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_saida_id_seq'::regclass)
turno_id  bigint  NOT NULL
chave  text  NOT NULL
ordem  integer  NOT NULL
tipo  text  NOT NULL
texto  text
imagem_url  text
codigo  integer
motivo  text
enviar_apos  timestamp with time zone  NOT NULL  padrão now()
estado  text  NOT NULL  padrão 'simulado'::text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX core_saida_turno ON public.core_saida USING btree (turno_id, ordem)
CREATE UNIQUE INDEX core_saida_pkey ON public.core_saida USING btree (id)

## restrições
core_saida_check: CHECK ((((tipo = 'texto'::text) AND (texto IS NOT NULL)) OR ((tipo = 'imagem'::text) AND (imagem_url IS NOT NULL) AND (codigo IS NOT NULL))))
core_saida_estado_check: CHECK ((estado = 'simulado'::text))
core_saida_pkey: PRIMARY KEY (id)
core_saida_tipo_check: CHECK ((tipo = ANY (ARRAY['texto'::text, 'imagem'::text])))
core_saida_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES core_turno(id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
