-- 384: a Nay da OLX guarda QUEM DEU O WHATSAPP, com a leitura de perfil, para a Nay do WhatsApp continuar
--
-- Pedro, 16/10/2026: "agora o nosso objetivo vai ser chamar a pessoa para o WhatsApp ... a Nay vai fazer uma leitura de
-- perfil ... aí a Nay de WhatsApp vai assumir já sabendo as coisas que a da OLX mandou". A Nay da OLX (nay-olx,
-- olx/nay.py) passa a pedir o WhatsApp; quando a pessoa dá, uma linha aqui: a conversa da OLX, o imóvel do anúncio, o
-- nome, o WhatsApp, se quis visitar e o perfil (procura, valor, bairros, quartos, financiamento, dúvidas).
-- A Nay do WhatsApp (número de captação, 92 8595-6408) ainda não existe: até lá a equipe chama, com o aviso no grupo,
-- como antes. `assumido_em` é dela: quando ela pegar a conversa.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.olx_lead_whatsapp (
  id          bigserial PRIMARY KEY,
  chat        bigint NOT NULL,          -- privado.olx_chat.id (sem chave estrangeira: o chat da OLX é escrito pelo CRM a cada mensagem)
  conta       text,
  list_id     text,
  codigo      integer,                  -- o imóvel do anúncio
  negocio     text,                     -- venda | locacao (do anúncio)
  nome        text,
  telefone    text NOT NULL,            -- só dígitos, com DDD (sem o 55)
  quer_visita boolean NOT NULL DEFAULT false,
  perfil      jsonb NOT NULL DEFAULT '{}'::jsonb,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  assumido_em timestamptz,              -- quando a Nay do WhatsApp pegou
  UNIQUE (chat, telefone)
);
COMMENT ON TABLE privado.olx_lead_whatsapp IS
  '384: quem deu o WhatsApp no chat da OLX, com a leitura de perfil da Nay da OLX, para a Nay do WhatsApp continuar.';

CREATE OR REPLACE FUNCTION public.olx_nay_lead_whatsapp(p_chat bigint, p_nome text, p_telefone text, p_quer_visita boolean,
                                                        p_perfil jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_fone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_id   bigint;
BEGIN
  IF v_fone LIKE '55%' AND length(v_fone) IN (12, 13) THEN v_fone := substr(v_fone, 3); END IF;
  IF length(v_fone) NOT IN (10, 11) THEN RETURN NULL; END IF;
  INSERT INTO privado.olx_lead_whatsapp AS l (chat, conta, list_id, codigo, negocio, nome, telefone, quer_visita, perfil)
  SELECT c.id, c.conta, c.list_id, a.codigo, a.negocio, nullif(btrim(coalesce(p_nome, '')), ''), v_fone,
         coalesce(p_quer_visita, false), coalesce(p_perfil, '{}'::jsonb)
    FROM privado.olx_chat c
    LEFT JOIN LATERAL (SELECT x.codigo, x.negocio FROM privado.olx_anuncio x WHERE x.list_id = c.list_id
                        ORDER BY x.enviado_em DESC NULLS LAST, x.id DESC LIMIT 1) a ON true
   WHERE c.id = p_chat
  ON CONFLICT (chat, telefone) DO UPDATE
     SET nome = coalesce(EXCLUDED.nome, l.nome), quer_visita = l.quer_visita OR EXCLUDED.quer_visita,
         perfil = l.perfil || EXCLUDED.perfil, atualizado_em = now()
  RETURNING l.id INTO v_id;
  RETURN v_id;
END
$function$;
REVOKE ALL ON FUNCTION public.olx_nay_lead_whatsapp(bigint, text, text, boolean, jsonb) FROM PUBLIC;

COMMIT;
