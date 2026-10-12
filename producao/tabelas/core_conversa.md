# core_conversa  (tabela, ~190 linhas)

## colunas
chave  text  NOT NULL
estado  text  NOT NULL  padrão 'NOVO'::text
estado_desde  timestamp with time zone  NOT NULL  padrão now()
filtro_finalidade  text
filtro_tipo  text
filtro_teto  numeric
filtro_teto_tanto_faz  boolean  NOT NULL  padrão false
filtro_regiao  text[]
filtro_regiao_tanto_faz  boolean  NOT NULL  padrão false
filtro_quartos  integer
filtro_mobilia  text
veio_do_grupo  boolean  NOT NULL  padrão false
foco_codigo  integer
foco_origem  text
foco_desde  timestamp with time zone
mostrados  integer[]  NOT NULL  padrão '{}'::integer[]
rejeitados  integer[]  NOT NULL  padrão '{}'::integer[]
visita_sugerida_em  timestamp with time zone
visita_pedida  jsonb
escalado_motivo  text
escalado_ate  timestamp with time zone
humano_ate  timestamp with time zone
versao  integer  NOT NULL  padrão 0
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
ultima_pergunta  text
ultima_acao  text
ultima_lista  integer[]  NOT NULL  padrão '{}'::integer[]
ultima_acao_em  timestamp with time zone
filtro_extras  text[]  NOT NULL  padrão '{}'::text[]
filtro_piso  numeric
pergunta_vezes  integer  NOT NULL  padrão 0
pedido_desde  timestamp with time zone

## índices
CREATE INDEX core_conversa_estado ON public.core_conversa USING btree (estado)
CREATE UNIQUE INDEX core_conversa_pkey ON public.core_conversa USING btree (chave)

## restrições
core_conversa_estado_check: CHECK ((estado = ANY (ARRAY['NOVO'::text, 'IDENTIFICANDO'::text, 'FILTRO_FINALIDADE'::text, 'FILTRO_TIPO'::text, 'FILTRO_TETO'::text, 'FILTRO_REGIAO'::text, 'FILTRO_MOBILIA'::text, 'FILTRO_CLIMATIZADO'::text, 'BUSCA'::text, 'APRESENTADO'::text, 'VISITA_PEDIDA'::text, 'ESCALADO'::text, 'HUMANO'::text, 'SILENCIO'::text])))
core_conversa_filtro_finalidade_check: CHECK ((filtro_finalidade = ANY (ARRAY['locacao'::text, 'venda'::text, 'ambos'::text, 'tanto_faz'::text])))
core_conversa_filtro_mobilia_check: CHECK ((filtro_mobilia = ANY (ARRAY['mobiliado'::text, 'semi'::text, 'nao'::text, 'tanto_faz'::text, 'sem_preferencia'::text, 'climatizado'::text])))
core_conversa_pkey: PRIMARY KEY (chave)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
