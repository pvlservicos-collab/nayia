# privado.nay_leads_dono_pergunta  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.nay_leads_dono_pergunta_id_seq'::regclass)
fila  bigint
telefone  text  NOT NULL
nome  text
texto  text  NOT NULL
estado  text  NOT NULL  padrão 'pendente'::text
linha  text
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
enviado_em  timestamp with time zone

## índices
CREATE INDEX nay_leads_dono_pergunta_pendente ON privado.nay_leads_dono_pergunta USING btree (id) WHERE (estado = 'pendente'::text)
CREATE UNIQUE INDEX nay_leads_dono_pergunta_pkey ON privado.nay_leads_dono_pergunta USING btree (id)

## restrições
nay_leads_dono_pergunta_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'enviada'::text, 'erro'::text])))
nay_leads_dono_pergunta_linha_check: CHECK ((linha = ANY (ARRAY['captacao'::text, 'parceria'::text])))
nay_leads_dono_pergunta_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
nay_leads_perguntar_ao_dono

## funções que citam
nay_leads_perguntar_ao_dono
