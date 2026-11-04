# privado.campanha_baixa  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.campanha_baixa_id_seq'::regclass)
codigo  integer  NOT NULL
finalidade  text  NOT NULL
valor_antes  numeric  NOT NULL
valor_novo  numeric  NOT NULL
contato  bigint
quem  text  NOT NULL
estado  text  NOT NULL  padrão 'confirmada'::text
motivo  text
confirmada_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX campanha_baixa_aberta ON privado.campanha_baixa USING btree (codigo, finalidade) WHERE (estado = ANY (ARRAY['confirmada'::text, 'avisando'::text]))
CREATE UNIQUE INDEX campanha_baixa_pkey ON privado.campanha_baixa USING btree (id)

## restrições
campanha_baixa_check: CHECK (((valor_novo > (0)::numeric) AND (valor_novo < valor_antes)))
campanha_baixa_contato_fkey: FOREIGN KEY (contato) REFERENCES privado.campanha_contato(id)
campanha_baixa_estado_check: CHECK ((estado = ANY (ARRAY['confirmada'::text, 'avisando'::text, 'avisada'::text, 'expirada'::text, 'cancelada'::text])))
campanha_baixa_finalidade_check: CHECK ((finalidade = ANY (ARRAY['locacao'::text, 'venda'::text])))
campanha_baixa_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
