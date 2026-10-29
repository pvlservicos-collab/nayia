# privado.aviso_equipe  (tabela, ~113 linhas)
508 (28/10): o aviso à equipe que não é de visita; o CRM leva às Notificações (crm_avisos_da_equipe).

## colunas
id  bigint  NOT NULL  padrão nextval('privado.aviso_equipe_id_seq'::regclass)
fonte  text  NOT NULL
tipo  text  NOT NULL
titulo  text  NOT NULL
texto  text  NOT NULL
telefone  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX aviso_equipe_pkey ON privado.aviso_equipe USING btree (id)

## restrições
aviso_equipe_pkey: PRIMARY KEY (id)
aviso_equipe_tipo_check: CHECK ((tipo = ANY (ARRAY['escalada'::text, 'duvida'::text, 'midia'::text, 'relatorio'::text, 'lead'::text, 'outro'::text, 'nota'::text])))

## permissões
(só o dono)

## funções que escrevem aqui
nay_aviso_equipe

## funções que citam
crm_avisos_da_equipe, crm_notas_da_nay, nay_aviso_equipe
