# privado.agente_evento  (tabela, ~1907 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.agente_evento_id_seq'::regclass)
canal  text  NOT NULL  padrão 'leads'::text
lead_id  bigint
chave8  text
agente  text  NOT NULL
acao  text  NOT NULL
turno  text
decisao  jsonb  NOT NULL  padrão '{}'::jsonb
confianca  numeric(6,4)
ms  integer
tokens_entrada  integer
tokens_cache  integer
tokens_saida  integer
custo_usd  numeric(14,8)
modelo  text
modo  text  NOT NULL  padrão 'real'::text
erro  text
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX agente_evento_agente_em ON privado.agente_evento USING btree (agente, em)
CREATE INDEX agente_evento_chave8_em ON privado.agente_evento USING btree (chave8, em DESC)
CREATE INDEX agente_evento_em ON privado.agente_evento USING btree (em DESC)
CREATE INDEX agente_evento_modo_em ON privado.agente_evento USING btree (modo, em)
CREATE INDEX agente_evento_turno ON privado.agente_evento USING btree (turno) WHERE (turno IS NOT NULL)
CREATE UNIQUE INDEX agente_evento_pkey ON privado.agente_evento USING btree (id)

## restrições
agente_evento_agente_fkey: FOREIGN KEY (agente) REFERENCES privado.agente(chave)
agente_evento_modo_check: CHECK ((modo = ANY (ARRAY['real'::text, 'sombra'::text, 'replay'::text])))
agente_evento_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_agentes_painel, crm_agentes_tracos
