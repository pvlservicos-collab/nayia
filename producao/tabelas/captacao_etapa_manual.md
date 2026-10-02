# captacao_etapa_manual  (tabela, ~0 linhas)
242: a etapa da captação escolhida no CRM; vale mais que a deduzida pela campanha

## colunas
telefone  text  NOT NULL
etapa  text  NOT NULL
definido_por  text
definido_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX captacao_etapa_manual_pkey ON public.captacao_etapa_manual USING btree (telefone)

## restrições
captacao_etapa_manual_ok: CHECK ((etapa = ANY (ARRAY['todos'::text, 'em_andamento'::text, 'followup'::text, 'disponiveis'::text, 'alugados'::text, 'quer_vender'::text, 'ja_vendeu'::text, 'tem_outro_imovel'::text, 'sem_resposta'::text, 'com_o_tel'::text])))
captacao_etapa_manual_pkey: PRIMARY KEY (telefone)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
crm_captacao_etapa_manual

## funções que citam
crm_captacao_dono_cadastro, crm_captacao_donos, crm_captacao_etapa_manual
