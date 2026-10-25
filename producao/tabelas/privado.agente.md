# privado.agente  (tabela, ~0 linhas)

## colunas
chave  text  NOT NULL
nome  text  NOT NULL
cor  text  NOT NULL
ordem  integer  NOT NULL  padrão 0
descricao  text  NOT NULL  padrão ''::text
canal  text  NOT NULL  padrão 'leads'::text
tipo  text  NOT NULL  padrão 'ia'::text
modelo  text
ligado  boolean  NOT NULL  padrão true
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX agente_pkey ON privado.agente USING btree (chave)

## restrições
agente_pkey: PRIMARY KEY (chave)
agente_tipo_check: CHECK ((tipo = ANY (ARRAY['ia'::text, 'codigo'::text, 'gente'::text])))

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_agentes, crm_agentes_do_lead, crm_agentes_painel, crm_agentes_tracos
