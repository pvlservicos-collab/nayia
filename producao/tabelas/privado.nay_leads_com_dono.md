# privado.nay_leads_com_dono  (tabela, ~0 linhas)
492: a Nay Leads está conversando com este proprietário pela linha da Parceria (o CRM pinta a conversa de roxo).

## colunas
chave  text  NOT NULL
telefone  text  NOT NULL
nome  text
motivo  text
lead  bigint
desde  timestamp with time zone  NOT NULL  padrão now()
ate  timestamp with time zone  NOT NULL

## índices
CREATE UNIQUE INDEX nay_leads_com_dono_pkey ON privado.nay_leads_com_dono USING btree (chave)

## restrições
nay_leads_com_dono_pkey: PRIMARY KEY (chave)

## permissões
(só o dono)

## funções que escrevem aqui
nay_leads_mandar_pela_parceria, nay_leads_soltar_dono

## funções que citam
crm_nay_leads_com_dono, nay_leads_mandar_pela_parceria, nay_leads_soltar_dono
