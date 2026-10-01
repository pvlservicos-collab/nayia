-- 01/10/2026: a conversa da Alessandra Barros (92 98127-1044) na etapa do Tel,
-- com observação no card e o aviso para ele no CRM. Pedido do Pedro no chat.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL ROLE crm;

UPDATE leads SET
  custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
    || jsonb_build_object('etapa_parceria', 'tel', 'etapa_parceria_em', now()::text,
         'observacao', 'Conversa de 15/09 trazida da Nay para o CRM em 01/10, a pedido do Pedro. Sao as 6 mensagens que o nosso sistema gravou naquele dia (19:47 as 20:05), todas dela -- a ultima: "Vcs podem vender normal sem permuta". A Z-API nao devolve historico em multi-dispositivo, entao o que voce respondeu pelo celular nao esta no nosso registro.'),
  is_archived = false,
  updated_at = now()
 WHERE id = '93898757-5244-463f-84a8-aac84238515e'::uuid
   AND organization_id = 'a47991bb-80e3-43ad-9838-02258ebac5d2'::uuid;

INSERT INTO notifications (organization_id, recipient_member_id, type, title, body, metadata)
VALUES ('a47991bb-80e3-43ad-9838-02258ebac5d2'::uuid,
        'b72966e7-ce42-4767-af86-5626d195a4ee'::uuid,
        'inbound_message',
        'Alessandra Barros esta na sua etapa',
        'A conversa de 15/09 dela foi trazida da Nay para o CRM (6 mensagens, a ultima: "Vcs podem vender normal sem permuta"). Pedro pediu para te avisar. A Nay nao responde essa pessoa ate voce devolver.',
        jsonb_build_object('linkUrl', '/chat/parceria?leadId=93898757-5244-463f-84a8-aac84238515e',
                           'leadId', '93898757-5244-463f-84a8-aac84238515e'));
COMMIT;
