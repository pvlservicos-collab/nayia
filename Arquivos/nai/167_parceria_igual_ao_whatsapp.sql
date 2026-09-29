-- =====================================================================
-- 167 — A CONVERSA DA PARCERIA NO CRM IGUAL AO WHATSAPP (29/09/2026)
--
-- Pedro: "as conversas da parceria eu preciso que fique exatamente como está
-- no meu whatsapp aqui ... tem mensagem que não aparece".
--
-- Medido em 29/09 (3 dias, mensagens da Nay x CRM): 555 de 755 respostas
-- de texto e 220 de 242 fotos para contatos com @lid faltavam no CRM -- o eco
-- da NOSSA mensagem chega com o LID no lugar do telefone, e o CRM jogava fora
-- número de 15 dígitos como se fosse "comunidade". E o que não passa pela NAI
-- (comando do Tel, card do publicador, equipe) nunca chegava: o espelho para
-- o CRM mora só no fluxo da NAI.
--
-- Do lado da Nay, duas leituras para o CRM (papel `nay_disparo`):
--   crm_telefone_do_lid(lid)      o telefone de um @lid (identidade_lid)
--   crm_mensagens_da_parceria()   as mensagens do número da Parceria num
--       intervalo -- o CRM confere a cada minuto o que não chegou e traz.
--
-- E conserta a 166: `identidade_lid.lid` vem nos dois formatos ("2439...@lid"
-- em 157 linhas, só números em 1.463), e a chave da Nay é 'lid:' + números.
-- Sem tirar o sufixo, o telefone e o @lid da mesma pessoa não se juntavam.
-- (A mesma diferença existe em `nai_contato_irmaos`, da Nay -- anotado, não
-- mexido aqui: ~22 contatos com @lid não se juntam ao telefone por isso.)
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION crm_pessoas(p_telefones text[])
RETURNS TABLE(telefone text, contato_id bigint, ids bigint[], chaves text[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH entrada AS (
    SELECT DISTINCT t AS telefone FROM unnest(coalesce(p_telefones, ARRAY[]::text[])) AS t
     WHERE coalesce(t, '') <> '' LIMIT 3000
  ),
  lid_map AS MATERIALIZED (
    SELECT 'lid:' || regexp_replace(i.lid, '\D', '', 'g') AS lid_chave, nai_chave(i.telefone) AS fone_chave
      FROM identidade_lid i WHERE coalesce(i.telefone, '') <> ''
  ),
  cand AS (
    SELECT e.telefone, x.chave
      FROM entrada e
      CROSS JOIN LATERAL (SELECT regexp_replace(e.telefone, '\D', '', 'g') AS dig) d
      CROSS JOIN LATERAL unnest(ARRAY[
        CASE WHEN d.dig ~ '^55[0-9]{10,11}$' OR length(d.dig) IN (10, 11) THEN nai_chave(d.dig) END,
        CASE WHEN d.dig !~ '^55[0-9]{10,11}$' AND length(d.dig) BETWEEN 12 AND 20 THEN 'lid:' || d.dig END
      ]) AS x(chave)
     WHERE x.chave IS NOT NULL
  ),
  chaves AS MATERIALIZED (      -- o telefone e o @lid da mesma pessoa
    SELECT c.telefone, c.chave FROM cand c
    UNION SELECT c.telefone, m.fone_chave FROM cand c JOIN lid_map m ON m.lid_chave = c.chave
    UNION SELECT c.telefone, m.lid_chave  FROM cand c JOIN lid_map m ON m.fone_chave = c.chave
  ),
  contatos AS MATERIALIZED (
    SELECT ch.telefone, nc.id FROM chaves ch JOIN nai_contato nc ON nc.chave = ch.chave
  )
  SELECT e.telefone,
         (SELECT min(c.id) FROM contatos c WHERE c.telefone = e.telefone),
         ARRAY(SELECT DISTINCT c.id FROM contatos c WHERE c.telefone = e.telefone),
         ARRAY(SELECT ch.chave FROM chaves ch WHERE ch.telefone = e.telefone ORDER BY ch.chave)
    FROM entrada e
$$;

CREATE OR REPLACE FUNCTION crm_visitas(p_desde date DEFAULT NULL, p_ate date DEFAULT NULL)
RETURNS TABLE(id bigint, codigo int, imovel text, estado text, aberta boolean, aguardando text, urgente boolean,
              acesso text, quando timestamptz, quando_sugerido timestamptz,
              criado_em timestamptz, confirmada_corretor_em timestamptz, aprovada_em timestamptz, aprovada_por text,
              prop_ok_em timestamptz, moto_ok_em timestamptz, confirmada_em timestamptz, pos_visita_em timestamptz,
              encerrada_em timestamptz, atualizado_em timestamptz, resultado text, motivo text,
              corretor_nome text, corretor_chaves text[], proprietario_nome text, visitante_nome text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  -- `nai_chave` custa ~30 us: por visita, contra 1.538 corretores e 1.620
  -- @lid, eram 5 s (medido em 29/09). Calculadas uma vez só, aqui.
  WITH corr AS MATERIALIZED (
    SELECT nai_chave(cr.telefone) AS chave, cr.nome FROM corretores cr
  ),
  lid_map AS MATERIALIZED (
    SELECT 'lid:' || regexp_replace(i.lid, '\D', '', 'g') AS lid_chave, nai_chave(i.telefone) AS fone_chave
      FROM identidade_lid i WHERE coalesce(i.telefone, '') <> ''
  )
  SELECT v.id, v.codigo, nai_ref_imovel(v.codigo), v.estado, nai_visita_aberta(v.estado), v.aguardando,
         coalesce(v.urgente, false), v.acesso, v.quando, v.quando_sugerido,
         v.criado_em, v.confirmada_corretor_em, v.aprovada_em, v.aprovada_por,
         v.prop_ok_em, v.moto_ok_em, v.confirmada_em, v.pos_visita_em,
         v.encerrada_em, v.atualizado_em, v.resultado, v.motivo,
         coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(co.nome), ''), nullif(btrim(c.nome_whatsapp), '')),
         ARRAY(SELECT DISTINCT x FROM (
                 SELECT c.chave
                 UNION SELECT m.fone_chave FROM lid_map m WHERE m.lid_chave = c.chave
                 UNION SELECT m.lid_chave FROM lid_map m WHERE m.fone_chave = c.chave
               ) u(x) WHERE x IS NOT NULL),
         v.proprietario_nome, v.visitante_nome
    FROM nai_visita v
    LEFT JOIN nai_contato c ON c.id = v.corretor_id
    LEFT JOIN LATERAL (SELECT cr.nome FROM corr cr WHERE cr.chave = c.chave LIMIT 1) co ON true
   WHERE v.estado <> 'coletando'
     AND (nai_visita_aberta(v.estado)
          OR ((p_desde IS NULL OR coalesce(v.quando, v.criado_em) >= p_desde::timestamptz)
              AND (p_ate IS NULL OR coalesce(v.quando, v.criado_em) < (p_ate + 1)::timestamptz)))
   ORDER BY nai_visita_aberta(v.estado) DESC, coalesce(v.quando, v.criado_em) DESC
   LIMIT 500
$$;

-- O telefone de um @lid, pelo que a Nay aprendeu (a mensagem DO CONTATO traz
-- os dois). Aceita "2439...@lid", "lid:2439..." ou só os números.
CREATE OR REPLACE FUNCTION crm_telefone_do_lid(p_lid text)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  SELECT nai_fone_br(i.telefone)
    FROM identidade_lid i
   WHERE regexp_replace(i.lid, '\D', '', 'g') = regexp_replace(coalesce(p_lid, ''), '\D', '', 'g')
     AND coalesce(i.telefone, '') <> ''
   ORDER BY i.criado_em DESC NULLS LAST
   LIMIT 1
$$;

-- As mensagens do número da Parceria num intervalo, na ordem em que
-- aconteceram. É a fonte da conferência do CRM: o que tem aqui e não tem lá
-- entra lá (sem aviso, sem "não lida": é o histórico que faltava).
CREATE OR REPLACE FUNCTION crm_mensagens_da_parceria(p_desde timestamptz, p_ate timestamptz DEFAULT now(), p_limite int DEFAULT 2000)
RETURNS TABLE(id int, telefone text, nome text, direcao text, origem text, texto text, midia text,
              duracao int, message_id text, criada_em timestamptz, citado_id text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  SELECT m.id, m.telefone, m.nome, m.direcao, m.origem, m.texto, coalesce(m.midia_url, m.audio_url),
         m.duracao_seg, m.message_id, m.criada_em, m.citado_id
    FROM mensagens m
   WHERE m.criada_em >= p_desde AND m.criada_em < coalesce(p_ate, now())
     AND coalesce(m.message_id, '') <> ''
   ORDER BY m.criada_em, m.id
   LIMIT greatest(1, least(coalesce(p_limite, 2000), 5000))
$$;

REVOKE ALL ON FUNCTION crm_telefone_do_lid(text), crm_mensagens_da_parceria(timestamptz, timestamptz, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_telefone_do_lid(text), crm_mensagens_da_parceria(timestamptz, timestamptz, int) TO nay_disparo;

COMMIT;
