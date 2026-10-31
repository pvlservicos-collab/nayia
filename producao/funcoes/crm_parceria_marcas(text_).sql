CREATE OR REPLACE FUNCTION public.crm_parceria_marcas(p_telefones text[])
 RETURNS TABLE(telefone text, contato_id bigint, proprietario boolean, proprietario_nome text, imoveis_do_dono text[], corretor boolean, corretor_nome text, creci text, visita_aberta boolean, visita_id bigint, visita_quando timestamp with time zone, visita_estado text, visita_papel text, visita_codigo integer, tel_atendendo boolean, tel_motivo text, etapa text, etapa_desde timestamp with time zone, equipe boolean, checklist boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH pessoa AS MATERIALIZED (SELECT * FROM crm_pessoas(p_telefones)),
  chave_da_pessoa AS MATERIALIZED (
    SELECT pe.telefone, unnest(pe.chaves) AS chave FROM pessoa pe
  ),
  -- 543: os 8 últimos dígitos de cada chave -- o filtro barato que vem ANTES do nai_chave dos cadastros abaixo
  fins AS MATERIALIZED (
    SELECT array_agg(DISTINCT right(regexp_replace(cp.chave, '\D', '', 'g'), 8)) AS f FROM chave_da_pessoa cp
  ),
  -- todo proprietário que o sistema conhece: o cadastro do site, o do admin
  -- antigo e quem a campanha de captação procurou
  donos AS MATERIALIZED (
    SELECT nai_chave(p.telefone) AS chave, p.nome, 'p'::text AS fonte, p.id::text AS ref
      FROM proprietarios p, fins WHERE coalesce(p.telefone, '') <> ''
       AND right(regexp_replace(p.telefone, '\D', '', 'g'), 8) = ANY (fins.f)
    UNION ALL
    SELECT nai_chave(a.telefone), a.nome, 'a', a.id::text FROM proprietarios_admin a, fins WHERE coalesce(a.telefone, '') <> ''
       AND right(regexp_replace(a.telefone, '\D', '', 'g'), 8) = ANY (fins.f)
    UNION ALL
    SELECT l.telefone_chave, l.nome, 'c', l.codigo FROM captacao_leads l, fins WHERE coalesce(l.telefone_chave, '') <> ''
       AND right(regexp_replace(l.telefone_chave, '\D', '', 'g'), 8) = ANY (fins.f)
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
      JOIN (SELECT nai_chave(c0.telefone) AS chave, c0.nome, c0.creci, c0.ativo FROM corretores c0, fins
             WHERE right(regexp_replace(coalesce(c0.telefone, ''), '\D', '', 'g'), 8) = ANY (fins.f)) c ON c.chave = cp.chave
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
         -- 288: O MOTIVO QUE VALE É O MAIS FORTE, não o mais recente. A pessoa tem duas
         -- linhas (telefone e @lid). Com a conversa escalada numa e o eco de uma mensagem
         -- à mão caindo na outra, o motivo mais recente era "o Tel escreveu pelo celular",
         -- e o CRM leria "pausa de 30 min" numa conversa que o Tel ASSUMIU. A marca que
         -- não é a pausa e ainda vale (escalada dentro do prazo, CRM, visita, Rayssa) vem
         -- na frente; a pausa só é o motivo quando é o ÚNICO.
         ORDER BY (c.humano_motivo IS DISTINCT FROM 'o Tel escreveu pelo celular'
                   AND NOT (c.humano_motivo ~ '^(duvida fora da base|midia)'
                            AND nai_cfg_int('escalacao_expira_horas', 0) > 0
                            AND c.humano_assumiu_em <= now() - make_interval(hours => nai_cfg_int('escalacao_expira_horas', 0)))) DESC,
                  c.humano_assumiu_em DESC LIMIT 1) u
  ),
  tel AS MATERIALIZED (
    SELECT u.telefone, u.motivo, coalesce(nai_tel_com_a_conversa(u.contato_id), false) AS com_o_tel
      FROM ultima u
     WHERE u.motivo IS DISTINCT FROM 'o Tel escreveu pelo celular'
        OR u.em > now() - make_interval(mins => greatest(nai_cfg_int('gap_tel_min', 30), 0))
  )
  SELECT pe.telefone, pe.contato_id,
         -- 173: corretor parceiro NÃO é proprietário (o nome dele aparece na
         -- captação e no cadastro por imóvel que ele anunciou), e a equipe (Tel,
         -- Rayssa) não é nem um nem outro
         ((dn.nome IS NOT NULL OR vp.id IS NOT NULL) AND co.telefone IS NULL AND NOT eq.equipe),
         CASE WHEN co.telefone IS NULL AND NOT eq.equipe THEN coalesce(dn.nome, vp.proprietario_nome) END,
         CASE WHEN co.telefone IS NULL AND NOT eq.equipe
              THEN ARRAY(SELECT x.codigo FROM imovel_do_dono x WHERE x.telefone = pe.telefone AND x.codigo ~ '^[0-9]+$'
                          ORDER BY x.codigo::int LIMIT 12)
              ELSE ARRAY[]::text[] END,
         (co.telefone IS NOT NULL AND NOT eq.equipe), co.nome, coalesce(co.creci, nc.creci),
         (va.id IS NOT NULL), va.id, va.quando, va.estado, va.papel, va.codigo,
         coalesce(t.com_o_tel, false), CASE WHEN t.com_o_tel THEN t.motivo END,
         et.etapa, et.desde, eq.equipe, ck.pediu
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
    -- 170: a etapa da Nay com a pessoa (as duas linhas, telefone e @lid)
    LEFT JOIN LATERAL (
      SELECT e.etapa, e.desde FROM nai_etapa_contato e
       WHERE e.contato_id = ANY (pe.ids) ORDER BY e.atualizado_em DESC NULLS LAST LIMIT 1
    ) et ON true
    -- 173: a equipe, pela regra única da Nay (tel_telefone, comando, equipe)
    LEFT JOIN LATERAL (
      SELECT coalesce(pe.contato_id IS NOT NULL AND nai_e_da_equipe_contato(pe.contato_id), false) AS equipe
    ) eq ON true
    -- 30/09: JA PEDIU O CHECKLIST? Quem pede a documentacao esta fechando --
    -- e a etapa Fechamento no CRM. O checklist sai pela caixa da Nay com
    -- motivo 'checklist_...' (nai_enviar_checklist_para); ter recebido e o
    -- sinal, porque so se manda a quem pediu.
    LEFT JOIN LATERAL (
      SELECT EXISTS (
        SELECT 1 FROM nai_saida s
         WHERE s.contato_id = ANY (pe.ids)
           AND s.motivo LIKE 'checklist%'
           AND s.estado IN ('enviado', 'enviando', 'simulado')) AS pediu
    ) ck ON true
$function$;
