# core_treino_resultado  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_treino_resultado_id_seq'::regclass)
execucao_id  bigint  NOT NULL
chave  text  NOT NULL
turno_origem  bigint  NOT NULL
ordem  integer  NOT NULL
horario_original  timestamp with time zone  NOT NULL
texto  text
enviado_antes  jsonb
resposta_nova  jsonb
acao  text
template  text
imovel  integer[]
estado_depois  text
caminho  text
intencao  text
modelo_chamadas  integer  NOT NULL  padrão 0
custo  numeric
ms  integer
erro  text
igual_imovel  boolean

## índices
CREATE INDEX core_treino_resultado_conversa ON public.core_treino_resultado USING btree (execucao_id, chave, ordem)
CREATE INDEX core_treino_resultado_turno ON public.core_treino_resultado USING btree (turno_origem, id DESC)
CREATE UNIQUE INDEX core_treino_resultado_pkey ON public.core_treino_resultado USING btree (id)

## restrições
core_treino_resultado_execucao_id_fkey: FOREIGN KEY (execucao_id) REFERENCES core_treino_execucao(id) ON DELETE CASCADE
core_treino_resultado_pkey: PRIMARY KEY (id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
