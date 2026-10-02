# nai_estado_conversa  (tabela, ~232 linhas)
Estado estruturado da conversa. Substitui o envelope de texto que hoje polui a nai_memoria.

## colunas
contato_id  bigint  NOT NULL
codigo_foco  integer
foco_desde  timestamp with time zone
foco_origem  text
codigos_mostrados  integer[]  NOT NULL  padrão '{}'::integer[]
codigos_rejeitados  integer[]  NOT NULL  padrão '{}'::integer[]   -- Imoveis que a pessoa recusou. Nao existia antes -- e a causa de ela receber de volta o imovel que acabou de recusar.
visita_pendente  bigint
ultima_fala_dela  text
ultima_fala_em  timestamp with time zone
papel  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_estado_conversa_pkey ON public.nai_estado_conversa USING btree (contato_id)

## restrições
nai_estado_conversa_codigo_foco_fkey: FOREIGN KEY (codigo_foco) REFERENCES imoveis(codigo)
nai_estado_conversa_contato_id_fkey: FOREIGN KEY (contato_id) REFERENCES nai_contato(id)
nai_estado_conversa_pkey: PRIMARY KEY (contato_id)
nai_estado_conversa_visita_pendente_fkey: FOREIGN KEY (visita_pendente) REFERENCES nai_visita(id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_estado_gravar_v2

## funções que citam
nai_enfileirar_resposta_ferramentas, nai_estado_gravar_v2, nai_estado_v2, nai_fila_dos_outros_imoveis, nai_pode_enviar_codigo_v2
