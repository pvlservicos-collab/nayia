# regras  (tabela, ~47 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('regras_id_seq'::regclass)
texto  text  NOT NULL
contexto  text
ativa  boolean  padrão true
criada_em  timestamp with time zone  padrão now()

## índices
CREATE UNIQUE INDEX regras_pkey ON public.regras USING btree (id)

## restrições
regras_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
captacao_ficha_aviso, nai_buscar_por_perfil, nai_deve_atender, nai_pedir_visita, nai_sem_pergunta_de_identidade, nay_tratamento_por_nome
