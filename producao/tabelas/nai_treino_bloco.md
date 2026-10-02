# nai_treino_bloco  (tabela, ~227 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_treino_bloco_id_seq'::regclass)
conversa_id  bigint  NOT NULL
ordem  integer  NOT NULL
turno_origem  bigint
quando_original  timestamp with time zone
ele_disse  text
ela_antes  text
fotos_antes  integer  NOT NULL  padrão 0
ela_agora  text
fotos_agora  integer  NOT NULL  padrão 0
turno_novo  bigint
ferramentas  text[]  NOT NULL  padrão '{}'::text[]
intencao  text
confianca  real
atendente  text
cortes  text
estado  text  NOT NULL  padrão 'pendente'::text
erro  text
rodado_em  timestamp with time zone

## índices
CREATE INDEX nai_treino_bloco_conversa ON public.nai_treino_bloco USING btree (conversa_id, ordem)
CREATE UNIQUE INDEX nai_treino_bloco_conversa_id_ordem_key ON public.nai_treino_bloco USING btree (conversa_id, ordem)
CREATE UNIQUE INDEX nai_treino_bloco_pkey ON public.nai_treino_bloco USING btree (id)

## restrições
nai_treino_bloco_conversa_id_fkey: FOREIGN KEY (conversa_id) REFERENCES nai_treino_conversa(id) ON DELETE CASCADE
nai_treino_bloco_conversa_id_ordem_key: UNIQUE (conversa_id, ordem)
nai_treino_bloco_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'rodado'::text, 'erro'::text])))
nai_treino_bloco_pkey: PRIMARY KEY (id)
nai_treino_bloco_turno_origem_fkey: FOREIGN KEY (turno_origem) REFERENCES nai_turno(id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_bloco_colher, nai_rodada_montar

## funções que citam
nai_bloco_colher, nai_rodada_montar
