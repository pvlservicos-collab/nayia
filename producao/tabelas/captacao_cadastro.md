# captacao_cadastro  (tabela, ~25 linhas)
A ficha que a Nay de captação monta na conversa (164): imóvel disponível a recadastrar ou imóvel novo do dono. Um humano aplica no painel.

## colunas
id  bigint  NOT NULL  padrão nextval('captacao_cadastro_id_seq'::regclass)
lead_id  bigint  NOT NULL
tipo  text  NOT NULL
codigo  integer
dados  jsonb  NOT NULL  padrão '{}'::jsonb
fotos  jsonb  NOT NULL  padrão '[]'::jsonb
estado  text  NOT NULL  padrão 'coletando'::text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
aplicado_em  timestamp with time zone
aplicado_por  text

## índices
CREATE INDEX captacao_cadastro_lead_idx ON public.captacao_cadastro USING btree (lead_id, estado)
CREATE UNIQUE INDEX captacao_cadastro_pkey ON public.captacao_cadastro USING btree (id)

## restrições
captacao_cadastro_estado_check: CHECK ((estado = ANY (ARRAY['coletando'::text, 'pronto'::text, 'aplicado'::text, 'descartado'::text])))
captacao_cadastro_pkey: PRIMARY KEY (id)
captacao_cadastro_tipo_check: CHECK ((tipo = ANY (ARRAY['atualizar'::text, 'novo'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: INSERT, SELECT, UPDATE

## funções que escrevem aqui
captacao_ficha, nai_cadastro_importar, site_juntar_cadastro

## funções que citam
captacao_ficha, captacao_ficha_aviso, captacao_fotos_a_puxar, crm_captacao_ficha_do_dono, crm_captacao_funil, crm_captacao_placar, crm_captacao_relatorio, nai_cadastro_importar, nai_cadastro_pendente, site_juntar_cadastro, site_origem_do_cadastro
