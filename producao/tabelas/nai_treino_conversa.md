# nai_treino_conversa  (tabela, ~34 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_treino_conversa_id_seq'::regclass)
rodada_id  bigint  NOT NULL
contato_origem  bigint  NOT NULL
nome  text
motivo  text
blocos_total  integer  NOT NULL  padrão 0
estado  text  NOT NULL  padrão 'pendente'::text
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
rodado_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX nai_treino_conversa_pkey ON public.nai_treino_conversa USING btree (id)
CREATE UNIQUE INDEX nai_treino_conversa_rodada_id_contato_origem_key ON public.nai_treino_conversa USING btree (rodada_id, contato_origem)

## restrições
nai_treino_conversa_contato_origem_fkey: FOREIGN KEY (contato_origem) REFERENCES nai_contato(id)
nai_treino_conversa_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'rodando'::text, 'rodado'::text, 'erro'::text])))
nai_treino_conversa_pkey: PRIMARY KEY (id)
nai_treino_conversa_rodada_id_contato_origem_key: UNIQUE (rodada_id, contato_origem)
nai_treino_conversa_rodada_id_fkey: FOREIGN KEY (rodada_id) REFERENCES nai_treino_rodada(id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_rodada_montar

## funções que citam
nai_rodada_montar
