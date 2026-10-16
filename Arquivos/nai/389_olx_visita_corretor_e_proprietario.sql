-- 389: a VISITA da Nay do WhatsApp dos clientes da OLX (92 8595-6408): confirmação ao cliente, o corretor, o proprietário
--
-- Pedro, 16/10/2026: "olha lá na captação primeiro fala com o corretor, e depois que ele confirmar, ou seja se não
-- confirmar que pode no horário chama outro, e depois só pergunta ao proprietário, e antes de chegar nisso ela deve mandar
-- uma mensagem de confirmação de visita igual é a mensagem da nay parceria, e só vai atrás dos contatos quando o lead
-- dizer sim" (e o modelo: "🏠 Só para confirmar a solicitação de visita ... Por favor, confirme se os dados estão
-- corretos para que eu possa entrar em contato com o proprietário").
--
-- O caminho (nay-olx/olx/visita.py):
--   confirmar_cliente  -> a confirmação foi ao cliente; espera o "sim"
--   buscando_corretor  -> um corretor de `visita_corretores` por vez; "não", ou sem resposta em `visita_corretor_espera_min`,
--                         chama o próximo; acabou a lista: sem_corretor (a equipe é avisada no grupo)
--   pedindo_proprietario -> com o corretor confirmado, o proprietário (nai_proprietario_do_imovel) pelo 8595-6408
--   confirmada         -> o proprietário confirmou: o cliente e o corretor recebem a visita confirmada
--   proprietario_nao / cancelada -> a equipe é avisada; o cliente escolhe outro horário
-- privado.olx_visita_consulta: cada pergunta a um corretor ou ao proprietário e a resposta. A mensagem de quem está sendo
-- consultado entra como 'Recebido olx' (o gatilho de 387): nem a Nay dos proprietários nem o n8n respondem por cima.
-- `visita_corretores` nasce vazio: os números da Raquel, da Neila e da Katherine ainda não estão em cadastro nenhum.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.olx_visita (
  id            bigserial PRIMARY KEY,
  lead          bigint NOT NULL,                 -- privado.olx_lead_whatsapp.id
  codigo        integer NOT NULL,
  quando        timestamptz NOT NULL,
  estado        text NOT NULL DEFAULT 'confirmar_cliente'
                CHECK (estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario', 'confirmada',
                                  'sem_corretor', 'proprietario_nao', 'sem_proprietario', 'cancelada')),
  corretor_nome text,
  corretor_telefone text,
  proprietario_nome text,
  proprietario_telefone text,
  cliente_confirmou_em timestamptz,
  confirmada_em timestamptz,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS olx_visita_lead ON privado.olx_visita (lead, criado_em DESC);
COMMENT ON TABLE privado.olx_visita IS '389: a visita pedida no WhatsApp de captação por um cliente da OLX, do pedido à confirmação.';

CREATE TABLE IF NOT EXISTS privado.olx_visita_consulta (
  id           bigserial PRIMARY KEY,
  visita       bigint NOT NULL,
  papel        text NOT NULL CHECK (papel IN ('corretor', 'proprietario')),
  nome         text,
  telefone     text NOT NULL,                    -- só dígitos, DDD + número
  perguntado_em timestamptz NOT NULL DEFAULT now(),
  ultima_lida  bigint NOT NULL DEFAULT 0,        -- captacao_mensagens.id
  estado       text NOT NULL DEFAULT 'esperando' CHECK (estado IN ('esperando', 'sim', 'nao', 'sem_resposta', 'cancelada')),
  resposta     text,
  respondido_em timestamptz
);
CREATE INDEX IF NOT EXISTS olx_visita_consulta_esperando ON privado.olx_visita_consulta (estado, telefone);
COMMENT ON TABLE privado.olx_visita_consulta IS '389: a pergunta da Nay a um corretor ou ao proprietário sobre uma visita, e a resposta.';

-- quem está sendo consultado sobre uma visita também é da Nay do WhatsApp (a resposta não vai para a Nay dos donos)
CREATE OR REPLACE FUNCTION public.captacao_mensagem_do_python()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.direcao = 'recebida' AND NEW.status = 'Recebido' THEN
    -- 387: quem está com a Nay do WhatsApp da OLX é dela; 389: e quem ela está consultando sobre uma visita
    IF EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o
                WHERE right(o.telefone, 8) = right(regexp_replace(coalesce(NEW.telefone, ''), '\D', '', 'g'), 8)
                  AND o.assumido_em IS NOT NULL AND o.etapa <> 'finalizado' AND o.humano_em IS NULL)
       OR EXISTS (SELECT 1 FROM privado.olx_visita_consulta c
                   WHERE c.estado = 'esperando'
                     AND right(c.telefone, 8) = right(regexp_replace(coalesce(NEW.telefone, ''), '\D', '', 'g'), 8)) THEN
      NEW.status := 'Recebido olx';
    ELSIF captacao_e_do_python(NEW.telefone) THEN
      NEW.status := 'Recebido py';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;

INSERT INTO privado.olx_config (chave, valor, descricao) VALUES
  ('visita_corretores', '', '389: os corretores da visita, na ordem: Nome:telefone, Nome:telefone (a Nay pergunta um por vez)'),
  ('visita_corretor_espera_min', '30', '389: minutos sem resposta do corretor antes de chamar o próximo'),
  ('visita_proprietario_espera_min', '180', '389: minutos sem resposta do proprietário antes de avisar a equipe')
ON CONFLICT (chave) DO NOTHING;

COMMIT;
