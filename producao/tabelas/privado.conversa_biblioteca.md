# privado.conversa_biblioteca  (tabela, ~851 linhas)
498: a biblioteca de conversas (certo × erro) da aba Inteligência; base do treino futuro.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.conversa_biblioteca_id_seq'::regclass)
nay  text  NOT NULL
ref  text  NOT NULL
dia  date
tel4  text
pessoa  text
resultado  text  NOT NULL
confianca  text  NOT NULL
nota  integer
fontes  text[]  NOT NULL  padrão '{}'::text[]
tipos  text[]  NOT NULL  padrão '{}'::text[]
resumo  text
marcas  jsonb  NOT NULL  padrão '[]'::jsonb
texto  text
usar_no_treino  boolean  NOT NULL  padrão true
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX conversa_biblioteca_dia ON privado.conversa_biblioteca USING btree (dia DESC)
CREATE UNIQUE INDEX conversa_biblioteca_nay_ref_key ON privado.conversa_biblioteca USING btree (nay, ref)
CREATE UNIQUE INDEX conversa_biblioteca_pkey ON privado.conversa_biblioteca USING btree (id)

## restrições
conversa_biblioteca_nay_ref_key: UNIQUE (nay, ref)
conversa_biblioteca_pkey: PRIMARY KEY (id)
conversa_biblioteca_resultado_check: CHECK ((resultado = ANY (ARRAY['certo'::text, 'erro'::text])))

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_biblioteca, site_biblioteca_conversa
