# privado.campanha_baixa_aviso  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.campanha_baixa_aviso_id_seq'::regclass)
baixa  bigint  NOT NULL
codigo  integer  NOT NULL
lead  bigint  NOT NULL
tel8  text  NOT NULL
estado  text  NOT NULL  padrão 'enviando'::text
texto  text
message_id  text
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
enviado_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX campanha_baixa_aviso_pkey ON privado.campanha_baixa_aviso USING btree (id)
CREATE UNIQUE INDEX campanha_baixa_aviso_uma_vez ON privado.campanha_baixa_aviso USING btree (codigo, tel8)

## restrições
campanha_baixa_aviso_baixa_fkey: FOREIGN KEY (baixa) REFERENCES privado.campanha_baixa(id)
campanha_baixa_aviso_estado_check: CHECK ((estado = ANY (ARRAY['enviando'::text, 'enviado'::text, 'erro'::text])))
campanha_baixa_aviso_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
