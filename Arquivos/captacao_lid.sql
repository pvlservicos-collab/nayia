-- =====================================================================
-- Captacao: o LID do chat (11/09/2026).
--
-- O CASO: o Tel respondeu a Sra. Wanessa (lead 510) pelo celular do numero
-- da campanha, e a regra "o Tel assumiu" NAO marcou o lead. A Z-API manda a
-- mensagem que ELE digita com phone = "3225637920810@lid" (o LID do chat),
-- sem o telefone real. A mensagem que ELA manda traz os dois: phone =
-- 559288430093 e chatLid = 3225637920810@lid.
--
-- Entao: toda mensagem RECEBIDA grava o LID no lead (chat_lid), e a do Tel
-- acha o lead pelo LID. Aditivo: coluna nova, anulavel; nada e apagado.
-- =====================================================================
ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS chat_lid text;
CREATE INDEX IF NOT EXISTS captacao_leads_chat_lid ON captacao_leads (chat_lid) WHERE chat_lid IS NOT NULL;

-- Acha o lead por telefone OU pelo LID (so digitos, com ou sem "@lid").
CREATE OR REPLACE FUNCTION captacao_lead_por_contato(p_tel text)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    (SELECT id FROM captacao_leads WHERE telefone_chave = nay_fone_chave(p_tel)
      AND coalesce(p_tel, '') !~* '@lid' AND length(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g')) BETWEEN 12 AND 13
      AND regexp_replace(coalesce(p_tel, ''), '\D', '', 'g') ~ '^55' LIMIT 1),
    (SELECT id FROM captacao_leads WHERE chat_lid = regexp_replace(coalesce(p_tel, ''), '\D', '', 'g')
      AND regexp_replace(coalesce(p_tel, ''), '\D', '', 'g') <> '' ORDER BY id DESC LIMIT 1));
$$;

-- ---------------------------------------------------------------------
-- Brechas fechadas (11/09, "de maneira nenhuma ela vai mais responder?"):
--
-- (a) O Tel escreveu para quem ainda nao respondeu nada: o LID dele ainda
--     nao estava em lead nenhum. Guarda o LID aqui; quando a pessoa
--     escrever (a mensagem dela traz telefone + LID), o lead ja nasce
--     'Com o Tel'.
CREATE TABLE IF NOT EXISTS captacao_lid_do_tel (
  lid       text PRIMARY KEY,
  em        timestamptz NOT NULL DEFAULT now(),
  texto     text
);

-- (b) O eco da API (o disparo/lembrete/resposta que NOS mandamos) traz o
--     telefone real E o chatLid: guarda o LID no lead ja no disparo.
CREATE OR REPLACE FUNCTION captacao_guardar_lid_do_eco(p_tel text, p_lid text)
RETURNS int LANGUAGE sql AS $$
  WITH u AS (
    UPDATE captacao_leads SET chat_lid = regexp_replace(p_lid, '\D', '', 'g')
     WHERE telefone_chave = nay_fone_chave(p_tel)
       AND regexp_replace(coalesce(p_tel, ''), '\D', '', 'g') ~ '^55'
       AND regexp_replace(coalesce(p_lid, ''), '\D', '', 'g') <> ''
       AND chat_lid IS DISTINCT FROM regexp_replace(p_lid, '\D', '', 'g')
    RETURNING 1)
  SELECT count(*)::int FROM u;
$$;

-- (c) Ultima conferencia antes de CADA balao sair: o lead ainda e da IA?
CREATE OR REPLACE FUNCTION captacao_ainda_e_da_ia(p_tel text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (SELECT 1 FROM captacao_leads
                      WHERE id = captacao_lead_por_contato(p_tel) AND humano_assumiu_em IS NOT NULL);
$$;
