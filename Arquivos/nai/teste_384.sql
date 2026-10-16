-- teste da 384 (na ensaio: termina em ROLLBACK)
SELECT olx_nay_lead_whatsapp(14, 'Michelle', '+55 92 98158-5907', false,
                             '{"procura": "apartamento para alugar, 2 quartos", "duvidas": "pediu detalhes"}') AS primeira;
-- de novo, agora querendo visitar e com o valor: atualiza a mesma linha
SELECT olx_nay_lead_whatsapp(14, NULL, '92981585907', true, '{"valor": "até R$ 3.000"}') AS segunda;
SELECT olx_nay_lead_whatsapp(14, 'x', '1234', false, '{}') AS numero_invalido;
SELECT chat, conta, codigo, negocio, nome, telefone, quer_visita, perfil FROM privado.olx_lead_whatsapp;
