-- 542 (Pedro, 30/10/2026: "cria uma integração pra gente no developers.grupozap.com, acessa o site e vê tudo o que
-- precisa para integrar"). Canal Pro (Grupo OLX: ZAP Imóveis, VivaReal, OLX) tem duas pontas:
--   1. o FEED: uma URL pública com o XML no formato VRSync, que o robô deles (VivaRealBot) baixa a cada 12 h
--      (nay-site-api/zap_api.py, /api/zap/imoveis.xml; os dados vêm de cnm_imoveis(), o mesmo cadastro do Chaves na Mão)
--   2. os LEADS: um POST em JSON por lead no nosso endereço (/api/zap/leads), com Authorization: Basic
--      base64(usuario:SECRET_KEY); a chave é dada pelo Grupo OLX na homologação, uma por CRM. Até 3 reenvios e o mesmo
--      lead pode vir repetido (originLeadId é a chave).
--
--   privado.zap_config   lead_segredo (a SECRET_KEY, quando vier)
--   privado.zap_lead     cada lead recebido, uma linha por originLeadId
--   zap_lead_receber()   confere a chave, guarda e diz se é novo, repetido, negado ou inválido
BEGIN;

CREATE TABLE IF NOT EXISTS privado.zap_config (chave text PRIMARY KEY, valor text);
COMMENT ON TABLE privado.zap_config IS '542: configuração da integração Canal Pro (Grupo OLX/ZAP): lead_segredo';
INSERT INTO privado.zap_config (chave, valor) VALUES ('lead_segredo', NULL) ON CONFLICT (chave) DO NOTHING;

CREATE TABLE IF NOT EXISTS privado.zap_lead (
  id             text PRIMARY KEY,                -- originLeadId
  recebido_em    timestamptz NOT NULL DEFAULT now(),
  vezes          integer NOT NULL DEFAULT 1,      -- quantas vezes chegou (reenvios)
  origem         text,                            -- leadOrigin: 'Grupo OLX' (anúncio) ou 'MCMV_OLX' (simulação)
  criado_em      timestamptz,                     -- timestamp do lead
  codigo         integer,                         -- clientListingId = o nosso código (ListingID do feed)
  anuncio_zap    text,                            -- originListingId
  nome           text,
  email          text,
  telefone       text,                            -- ddd + phone
  mensagem       text,
  temperatura    text,
  transacao      text,                            -- RENT / SELL
  canal          text,                            -- extraData.leadType
  autenticado    boolean NOT NULL DEFAULT false,
  dados          jsonb NOT NULL
);
COMMENT ON TABLE privado.zap_lead IS '542: os leads que o Canal Pro (Grupo OLX/ZAP) manda por webhook, um por originLeadId';

CREATE OR REPLACE FUNCTION public.zap_lead_receber(p jsonb, p_segredo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_chave text := nullif(btrim((SELECT valor FROM zap_config WHERE chave = 'lead_segredo')), '');
  v_id    text := nullif(btrim(p->>'originLeadId'), '');
  v_orig  text := nullif(btrim(p->>'leadOrigin'), '');
  v_cod   integer;
  v_novo  boolean;
BEGIN
  IF jsonb_typeof(p) IS DISTINCT FROM 'object' OR v_id IS NULL THEN
    RETURN jsonb_build_object('status', 'invalido', 'erro', 'falta o originLeadId');
  END IF;
  -- com a chave guardada, só passa quem a manda; sem ela (antes da homologação), entra marcado como não autenticado
  IF v_chave IS NOT NULL AND coalesce(p_segredo, '') <> v_chave THEN
    RETURN jsonb_build_object('status', 'negado');
  END IF;
  -- lead de anúncio sem o nosso código: 4xx para eles revisarem e reenviarem (a regra do Grupo OLX); MCMV não tem
  IF coalesce(v_orig, '') <> 'MCMV_OLX' AND nullif(btrim(p->>'clientListingId'), '') IS NULL THEN
    RETURN jsonb_build_object('status', 'invalido', 'erro', 'falta o clientListingId');
  END IF;
  v_cod := CASE WHEN btrim(p->>'clientListingId') ~ '^[0-9]{1,9}$' THEN (p->>'clientListingId')::integer END;

  INSERT INTO zap_lead (id, origem, criado_em, codigo, anuncio_zap, nome, email, telefone, mensagem, temperatura,
                        transacao, canal, autenticado, dados)
  VALUES (v_id, v_orig,
          CASE WHEN (p->>'timestamp') ~ '^\d{4}-\d{2}-\d{2}' THEN (p->>'timestamp')::timestamptz END,
          v_cod, nullif(p->>'originListingId', ''), nullif(btrim(p->>'name'), ''), nullif(btrim(p->>'email'), ''),
          nullif(regexp_replace(coalesce(p->>'ddd', '') || coalesce(p->>'phone', ''), '\D', '', 'g'), ''),
          p->>'message', p->>'temperature', p->>'transactionType', p#>>'{extraData,leadType}',
          v_chave IS NOT NULL, p)
  ON CONFLICT (id) DO UPDATE SET vezes = zap_lead.vezes + 1
  RETURNING (xmax = 0) INTO v_novo;
  RETURN jsonb_build_object('status', CASE WHEN v_novo THEN 'novo' ELSE 'repetido' END, 'id', v_id);
END
$function$;

REVOKE ALL ON FUNCTION public.zap_lead_receber(jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.zap_lead_receber(jsonb, text) TO nay_site_escrita;

COMMIT;
