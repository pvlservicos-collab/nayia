# identidade_lid  (tabela, ~1674 linhas)

## colunas
lid  text  NOT NULL
telefone  text  NOT NULL
nome  text
origem  text  NOT NULL  padrão 'nome'::text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX identidade_lid_chave ON public.identidade_lid USING btree (nai_chave(telefone))
CREATE UNIQUE INDEX identidade_lid_pkey ON public.identidade_lid USING btree (lid)

## restrições
identidade_lid_pkey: PRIMARY KEY (lid)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
nai_sincronizar_grupos, nay_resolver_identidade

## funções que citam
crm_pessoas, crm_telefone_do_lid, crm_visitas, nai_abrir_turno, nai_contato_irmaos, nai_pode_falar, nai_sincronizar_grupos, nai_tel_assumiu, nay_resolver_identidade
