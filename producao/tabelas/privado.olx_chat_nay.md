# privado.olx_chat_nay  (tabela, ~0 linhas)
364: o estado de cada conversa da OLX para a Nay: reservada (alguém está respondendo agora) e passada para gente (a Nay não responde mais nela).

## colunas
chat  bigint  NOT NULL
reservada_em  timestamp with time zone
reservada_por  text
humano_em  timestamp with time zone
humano_motivo  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
devolvida_em  timestamp with time zone   -- 374: quando a equipe devolveu a conversa para a Nay; mensagem de gente antes disso não cala mais a Nay

## índices
CREATE UNIQUE INDEX olx_chat_nay_pkey ON privado.olx_chat_nay USING btree (chat)

## restrições
olx_chat_nay_chat_fkey: FOREIGN KEY (chat) REFERENCES privado.olx_chat(id)
olx_chat_nay_pkey: PRIMARY KEY (chat)

## permissões
(só o dono)

## funções que escrevem aqui
olx_nay_devolver, olx_nay_passar_para_gente, olx_nay_reservar, olx_nay_soltar

## funções que citam
olx_nay_contexto, olx_nay_devolver, olx_nay_fila, olx_nay_passar_para_gente, olx_nay_reservar, olx_nay_soltar
