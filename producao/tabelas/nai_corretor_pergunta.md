# nai_corretor_pergunta  (tabela, ~0 linhas)
Quem escreveu para a NAI de fora da lista de corretores e ja foi perguntado ao Tel. decisao = resposta dele (CORRETOR / NAO CORRETOR).

## colunas
chave  text  NOT NULL
telefone  text  NOT NULL
nome  text
ultimo_texto  text
perguntado_em  timestamp with time zone  NOT NULL  padrão now()
turno_id  bigint
decisao  text
decidido_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX nai_corretor_pergunta_pkey ON public.nai_corretor_pergunta USING btree (chave)

## restrições
nai_corretor_pergunta_decisao_check: CHECK ((decisao = ANY (ARRAY['sim'::text, 'nao'::text])))
nai_corretor_pergunta_pkey: PRIMARY KEY (chave)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_decidir_corretor, nai_perguntar_se_e_corretor

## funções que citam
nai_decidir_corretor, nai_deve_atender, nai_followup_rodar, nai_perguntar_se_e_corretor, nai_pode_falar
