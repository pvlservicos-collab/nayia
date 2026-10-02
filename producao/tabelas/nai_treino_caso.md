# nai_treino_caso  (tabela, ~567 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_treino_caso_id_seq'::regclass)
ciclo_id  bigint  NOT NULL
turno_origem  bigint
contato_origem  bigint  NOT NULL
papel  text  NOT NULL
quando_original  timestamp with time zone  NOT NULL
ele_disse  text
ela_respondeu_antes  text
ferramentas_antes  text[]  NOT NULL  padrão '{}'::text[]
turno_simulado  bigint
ela_respondeu_agora  text
ferramentas_agora  text[]  NOT NULL  padrão '{}'::text[]
exec_id  text
estado  text  NOT NULL  padrão 'pendente'::text
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
rodado_em  timestamp with time zone
contexto  jsonb  NOT NULL  padrão '[]'::jsonb
msg_origem  integer
roteiro  text
passo  integer
persona  text

## índices
CREATE INDEX nai_treino_caso_ciclo ON public.nai_treino_caso USING btree (ciclo_id, id)
CREATE INDEX nai_treino_caso_estado ON public.nai_treino_caso USING btree (estado) WHERE (estado = 'pendente'::text)
CREATE UNIQUE INDEX nai_treino_caso_msg_origem_key ON public.nai_treino_caso USING btree (msg_origem) WHERE (msg_origem IS NOT NULL)
CREATE UNIQUE INDEX nai_treino_caso_pkey ON public.nai_treino_caso USING btree (id)
CREATE UNIQUE INDEX nai_treino_caso_turno_origem_key ON public.nai_treino_caso USING btree (turno_origem)

## restrições
nai_treino_caso_ciclo_id_fkey: FOREIGN KEY (ciclo_id) REFERENCES nai_treino_ciclo(id)
nai_treino_caso_contato_origem_fkey: FOREIGN KEY (contato_origem) REFERENCES nai_contato(id)
nai_treino_caso_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'rodando'::text, 'rodado'::text, 'erro'::text, 'calada'::text])))
nai_treino_caso_msg_origem_fkey: FOREIGN KEY (msg_origem) REFERENCES mensagens(id)
nai_treino_caso_origem_ok: CHECK (((turno_origem IS NOT NULL) OR (msg_origem IS NOT NULL) OR (roteiro IS NOT NULL)))
nai_treino_caso_pkey: PRIMARY KEY (id)
nai_treino_caso_turno_origem_fkey: FOREIGN KEY (turno_origem) REFERENCES nai_turno(id)
nai_treino_caso_turno_origem_key: UNIQUE (turno_origem)
nai_treino_caso_turno_simulado_fkey: FOREIGN KEY (turno_simulado) REFERENCES nai_turno(id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_treino_colher, nai_treino_montar_ciclo

## funções que citam
nai_treino_colher, nai_treino_montar_ciclo, nai_treino_semear_memoria
