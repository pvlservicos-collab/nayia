# privado.campanha_contato  (tabela, ~0 linhas)
595: campanhas que o Pedro libera à mão (parceiros_disponivel, donos_parados, feedback_disponiveis); nay-olx olx/campanhas.py manda as liberadas

## colunas
id  bigint  NOT NULL  padrão nextval('privado.campanha_contato_id_seq'::regclass)
lista  text  NOT NULL
dia  date  NOT NULL
nome  text
vocativo  text
telefone  text  NOT NULL
chave  text  NOT NULL
tel8  text  NOT NULL
linha  text  NOT NULL
modelo  text
modelo_valores  text[]
codigos  integer[]  NOT NULL
imoveis  jsonb  NOT NULL  padrão '[]'::jsonb
prioridade  integer  NOT NULL  padrão 0
falou_conosco_60d  boolean  NOT NULL  padrão false
mensagem  text  NOT NULL
mensagem_seguinte  text
estado  text  NOT NULL  padrão 'preparada'::text
liberada_em  timestamp with time zone
liberada_por  text
adiada_em  timestamp with time zone
adiada_motivo  text
outro_atende  text
enviada_em  timestamp with time zone
message_id  text
lida_ate  timestamp with time zone
resposta_em  timestamp with time zone
resposta_texto  text
classe  text
novo_valor  numeric
classe_codigos  integer[]
resumo  text
seguinte_em  timestamp with time zone
nossas  integer  NOT NULL  padrão 0
respondeu_quem  text
equipe_avisada_em  timestamp with time zone
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX campanha_contato_chave ON privado.campanha_contato USING btree (chave, enviada_em DESC)
CREATE INDEX campanha_contato_fila ON privado.campanha_contato USING btree (estado, prioridade DESC, id)
CREATE UNIQUE INDEX campanha_contato_pkey ON privado.campanha_contato USING btree (id)
CREATE UNIQUE INDEX campanha_contato_um_por_dia ON privado.campanha_contato USING btree (chave, dia) WHERE (estado <> 'cancelada'::text)

## restrições
campanha_contato_classe_check: CHECK ((classe = ANY (ARRAY['disponivel'::text, 'alugado'::text, 'vendido'::text, 'baixa'::text, 'outras_opcoes'::text, 'nao_e_comigo'::text, 'outra_coisa'::text])))
campanha_contato_estado_check: CHECK ((estado = ANY (ARRAY['preparada'::text, 'liberada'::text, 'enviando'::text, 'enviada'::text, 'respondida'::text, 'cancelada'::text, 'erro'::text])))
campanha_contato_linha_check: CHECK ((linha = ANY (ARRAY['parceria'::text, 'captacao'::text, 'oficial'::text])))
campanha_contato_lista_check: CHECK ((lista = ANY (ARRAY['parceiros_disponivel'::text, 'donos_parados'::text, 'feedback_disponiveis'::text])))
campanha_contato_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
campanha_quem_atende, campanha_reservar
