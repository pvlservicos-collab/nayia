SELECT chat, nome FROM olx_nay_fila(50);
SELECT chat, humano_em IS NOT NULL AS com_gente, humano_motivo FROM privado.olx_chat_nay WHERE chat = 26;
