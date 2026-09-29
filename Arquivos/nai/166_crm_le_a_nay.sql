-- =====================================================================
-- 166 — O CRM LÊ A NAY (29/09/2026)
--
-- Pedro, para a aba da Parceria no CRM:
--   "abas, primeiro chat, depois visitas agendadas ... que a ia preenche
--    sozinha quando confirma uma visita e a Rayssa pode acompanhar por lá o
--    andamento, e as datas de tudo";
--   "nas tags de cima ... TODOS, Não lidos, Proprietários (filtra conforme o
--    banco de dados, o sistema já sabe quem é), VISITAS, TEL (o Tel
--    atendendo)";
--   no card do lead, "o histórico do que aquele contato já pediu".
--
-- O CRM entra no banco da Nay pelo papel `nay_disparo`, que só EXECUTA
-- função (145) -- não lê tabela nenhuma. Estas são de LEITURA, SECURITY
-- DEFINER, e devolvem só o que a tela mostra: nada de senha de acesso, CPF
-- do visitante ou telefone de proprietário.
--
--   crm_parceria_marcas(telefones[])    por telefone de conversa: é
--       proprietário (e de quais imóveis), é corretor, tem visita aberta, o
--       Tel está com a conversa.
--   crm_visitas(desde, ate)             as visitas, com todas as datas.
--   crm_visita_eventos(visita)          o andamento, passo a passo.
--   crm_contato_historico(telefone, n)  o que a pessoa pediu, recebeu e
--       visitou, do mais novo para o mais velho.
--
-- AS CHAVES DA PESSOA: telefone (55+DDD+8, `nai_chave`) E o @lid do
-- WhatsApp -- 33 das 128 conversas da Parceria no CRM guardam o LID no
-- lugar do telefone (medido em 29/09). `crm_pessoas` junta os dois lados
-- como `nai_contato_irmaos`, mas para a lista toda de uma vez: aquela leva
-- ~100 ms por chamada, e 128 conversas estouravam um minuto.
--
-- `SET jit = off` em cada uma: a compilação JIT do Postgres custava 1,3 s
-- por chamada, mais que a consulta inteira (medido: 1,7 s -> 0,35 s).
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

-- A pessoa por trás de cada telefone do CRM (número ou LID).
CREATE OR REPLACE FUNCTION crm_pessoas(p_telefones text[])
RETURNS TABLE(telefone text, contato_id bigint, ids bigint[], chaves text[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH entrada AS (
    SELECT DISTINCT t AS telefone FROM unnest(coalesce(p_telefones, ARRAY[]::text[])) AS t
     WHERE coalesce(t, '') <> '' LIMIT 3000
  ),
  lid_map AS MATERIALIZED (
    SELECT 'lid:' || i.lid AS lid_chave, nai_chave(i.telefone) AS fone_chave
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

CREATE OR REPLACE FUNCTION crm_parceria_marcas(p_telefones text[])
RETURNS TABLE(telefone text, contato_id bigint,
              proprietario boolean, proprietario_nome text, imoveis_do_dono text[],
              corretor boolean, corretor_nome text, creci text,
              visita_aberta boolean, visita_id bigint, visita_quando timestamptz, visita_estado text,
              visita_papel text, visita_codigo int,
              tel_atendendo boolean, tel_motivo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH pessoa AS MATERIALIZED (SELECT * FROM crm_pessoas(p_telefones)),
  chave_da_pessoa AS MATERIALIZED (
    SELECT pe.telefone, unnest(pe.chaves) AS chave FROM pessoa pe
  ),
  -- todo proprietário que o sistema conhece: o cadastro do site, o do admin
  -- antigo e quem a campanha de captação procurou
  donos AS MATERIALIZED (
    SELECT nai_chave(p.telefone) AS chave, p.nome, 'p'::text AS fonte, p.id::text AS ref
      FROM proprietarios p WHERE coalesce(p.telefone, '') <> ''
    UNION ALL
    SELECT nai_chave(a.telefone), a.nome, 'a', a.id::text FROM proprietarios_admin a WHERE coalesce(a.telefone, '') <> ''
    UNION ALL
    SELECT l.telefone_chave, l.nome, 'c', l.codigo FROM captacao_leads l WHERE coalesce(l.telefone_chave, '') <> ''
  ),
  dono AS MATERIALIZED (
    SELECT cp.telefone, d.nome, d.fonte, d.ref FROM chave_da_pessoa cp JOIN donos d ON d.chave = cp.chave
  ),
  imovel_do_dono AS MATERIALIZED (
    SELECT dn.telefone, i.codigo::text AS codigo FROM dono dn JOIN imoveis i ON dn.fonte = 'p' AND i.proprietario_id::text = dn.ref
    UNION SELECT dn.telefone, ip.codigo::text FROM dono dn JOIN imovel_privado ip ON dn.fonte = 'p' AND ip.proprietario_id::text = dn.ref
    UNION SELECT dn.telefone, ai.codigo FROM dono dn JOIN proprietarios_admin_imoveis ai ON dn.fonte = 'a' AND ai.proprietario_id::text = dn.ref
    UNION SELECT dn.telefone, dn.ref FROM dono dn WHERE dn.fonte = 'c'
  ),
  corretor AS MATERIALIZED (
    SELECT DISTINCT ON (cp.telefone) cp.telefone, c.nome, c.creci
      FROM chave_da_pessoa cp
      JOIN (SELECT nai_chave(c0.telefone) AS chave, c0.nome, c0.creci, c0.ativo FROM corretores c0) c ON c.chave = cp.chave
     ORDER BY cp.telefone, c.ativo DESC NULLS LAST
  ),
  -- O TEL COM A CONVERSA: quem decide é a Nay (`nai_tel_com_a_conversa`, a
  -- leitura única da regra -- ver 54 e 130), e ela custa ~300 ms por chamada.
  -- 107 das 128 conversas têm alguma marca antiga; só 3 têm marca VIVA
  -- (medido em 29/09). Então ela só é chamada quando a resposta pode ser
  -- "sim": marca que não é "escreveu pelo celular" (escalada: vale até o
  -- DEVOLVER) ou "celular" ainda dentro da janela. Marca de celular vencida
  -- ela mesma responderia "não". SE A REGRA DO TEL MUDAR, REVEJA ESTE FILTRO.
  ultima AS MATERIALIZED (
    SELECT pe.telefone, pe.contato_id, u.em, u.motivo
      FROM pessoa pe
      CROSS JOIN LATERAL (
        SELECT c.humano_assumiu_em AS em, c.humano_motivo AS motivo FROM nai_contato c
         WHERE c.id = ANY (pe.ids) AND c.humano_assumiu_em IS NOT NULL
         ORDER BY c.humano_assumiu_em DESC LIMIT 1) u
  ),
  tel AS MATERIALIZED (
    SELECT u.telefone, u.motivo, coalesce(nai_tel_com_a_conversa(u.contato_id), false) AS com_o_tel
      FROM ultima u
     WHERE u.motivo IS DISTINCT FROM 'o Tel escreveu pelo celular'
        OR u.em > now() - make_interval(mins => greatest(nai_cfg_int('gap_tel_min', 30), 0))
  )
  SELECT pe.telefone, pe.contato_id,
         (dn.nome IS NOT NULL OR vp.id IS NOT NULL),
         coalesce(dn.nome, vp.proprietario_nome),
         ARRAY(SELECT x.codigo FROM imovel_do_dono x WHERE x.telefone = pe.telefone AND x.codigo ~ '^[0-9]+$'
                ORDER BY x.codigo::int LIMIT 12),
         (co.telefone IS NOT NULL), co.nome, coalesce(co.creci, nc.creci),
         (va.id IS NOT NULL), va.id, va.quando, va.estado, va.papel, va.codigo,
         coalesce(t.com_o_tel, false), CASE WHEN t.com_o_tel THEN t.motivo END
    FROM pessoa pe
    LEFT JOIN nai_contato nc ON nc.id = pe.contato_id
    LEFT JOIN LATERAL (SELECT min(d.nome) AS nome FROM dono d WHERE d.telefone = pe.telefone HAVING count(*) > 0) dn ON true
    LEFT JOIN LATERAL (
      SELECT v.id, v.proprietario_nome FROM nai_visita v WHERE v.proprietario_id = ANY (pe.ids) LIMIT 1
    ) vp ON true
    LEFT JOIN corretor co ON co.telefone = pe.telefone
    LEFT JOIN LATERAL (
      SELECT v.id, v.quando, v.estado, v.codigo,
             CASE WHEN v.corretor_id = ANY (pe.ids) THEN 'corretor' ELSE 'proprietario' END AS papel
        FROM nai_visita v
       WHERE (v.corretor_id = ANY (pe.ids) OR v.proprietario_id = ANY (pe.ids))
         AND nai_visita_aberta(v.estado)
       ORDER BY v.quando NULLS LAST LIMIT 1
    ) va ON true
    LEFT JOIN tel t ON t.telefone = pe.telefone
$$;

-- As visitas, com todas as datas. As abertas sempre vêm; as fechadas, na
-- janela pedida (padrão: tudo). 'coletando' é rascunho da Nay e não entra.
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
    SELECT 'lid:' || i.lid AS lid_chave, nai_chave(i.telefone) AS fone_chave
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

-- O andamento de uma visita, passo a passo (o registro que a Nay já grava).
CREATE OR REPLACE FUNCTION crm_visita_eventos(p_visita bigint)
RETURNS TABLE(quando timestamptz, tipo text, detalhe text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  SELECT e.quando, e.tipo, e.detalhe FROM nai_visita_evento e WHERE e.visita_id = p_visita ORDER BY e.quando, e.id
$$;

-- O que a pessoa pediu, recebeu e visitou. "recebeu" vem de `envios`, que
-- junta tudo o que saiu para ela (Nay, publicador, disparo do CRM); "pediu" é
-- o turno dela com um imóvel em foco; "visita" é a visita, com o estado.
CREATE OR REPLACE FUNCTION crm_contato_historico(p_telefone text, p_limite int DEFAULT 60)
RETURNS TABLE(quando timestamptz, tipo text, codigo int, imovel text, detalhe text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH p AS MATERIALIZED (SELECT * FROM crm_pessoas(ARRAY[p_telefone])),
  irmaos AS (SELECT unnest(p.ids) AS id FROM p),
  ev AS (
    SELECT e.enviado_em AS quando, 'recebeu'::text AS tipo,
           nullif(regexp_replace(coalesce(e.codigo, ''), '\D', '', 'g'), '')::int AS codigo, NULL::text AS detalhe
      FROM envios e, p
     WHERE e.destino IS DISTINCT FROM 'grupo' AND nai_chave(e.telefone) = ANY (p.chaves)
    UNION ALL
    SELECT t.criado_em, 'pediu', t.codigo, left(regexp_replace(coalesce(t.texto, ''), '\s+', ' ', 'g'), 160)
      FROM nai_turno t
     WHERE t.contato_id IN (SELECT id FROM irmaos) AND t.codigo IS NOT NULL AND NOT coalesce(t.teste, false)
    UNION ALL
    SELECT coalesce(v.quando, v.criado_em), 'visita', v.codigo, v.estado
      FROM nai_visita v
     WHERE v.estado <> 'coletando'
       AND (v.corretor_id IN (SELECT id FROM irmaos) OR v.proprietario_id IN (SELECT id FROM irmaos))
  )
  SELECT ev.quando, ev.tipo, ev.codigo, CASE WHEN ev.codigo IS NOT NULL THEN nai_ref_imovel(ev.codigo) END, ev.detalhe
    FROM ev WHERE ev.quando IS NOT NULL
   ORDER BY ev.quando DESC
   LIMIT greatest(1, least(coalesce(p_limite, 60), 300))
$$;

-- Só o CRM (e o dono do banco) executa. Função SECURITY DEFINER aberta ao
-- PUBLIC deixaria qualquer papel do banco ler por ela.
REVOKE ALL ON FUNCTION crm_pessoas(text[]), crm_parceria_marcas(text[]), crm_visitas(date, date),
                       crm_visita_eventos(bigint), crm_contato_historico(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_parceria_marcas(text[]), crm_visitas(date, date), crm_visita_eventos(bigint),
                          crm_contato_historico(text, int) TO nay_disparo;

COMMIT;
