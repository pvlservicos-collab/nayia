-- 170 -- a etapa da Nay e o "Nay ligada" no CRM (Pedro, 29/09/2026):
--   "quero uma tag no contato de em qual etapa a Nay está no contato, uma tag
--    pequena quadrada com essa etapa no lado direito do nome do contato" e
--   "uma tagzinha de robô ... para sabermos se a Nay está ou não ativa nesse
--    número ... verde ativa, vermelha inativa, ex. quando o Tel manda msg".
--
-- crm_parceria_marcas ganha etapa e etapa_desde (nai_etapa_contato, pelas
-- duas linhas da pessoa). Mudou o formato da resposta, então é DROP + CREATE
-- numa transação só (o CRM que está no ar ignora colunas a mais).
-- crm_nay_ligada(): a chave geral (modo e pausa) -- vermelho para todos quando
-- a Nay está parada. Por contato, o vermelho é o tel_atendendo que já existia
-- (o Tel com a conversa, ou o chat parado por uma visita).
-- Patch em cima da versão viva de 29/09.

BEGIN;
SET LOCAL lock_timeout = '5s';

DROP FUNCTION public.crm_parceria_marcas(text[]);
CREATE FUNCTION public.crm_parceria_marcas(p_telefones text[])
 RETURNS TABLE(telefone text, contato_id bigint, proprietario boolean, proprietario_nome text, imoveis_do_dono text[], corretor boolean, corretor_nome text, creci text, visita_aberta boolean, visita_id bigint, visita_quando timestamp with time zone, visita_estado text, visita_papel text, visita_codigo integer, tel_atendendo boolean, tel_motivo text, etapa text, etapa_desde timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
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
         coalesce(t.com_o_tel, false), CASE WHEN t.com_o_tel THEN t.motivo END,
         et.etapa, et.desde
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
$function$;

REVOKE ALL ON FUNCTION crm_parceria_marcas(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_parceria_marcas(text[]) TO nay_disparo;

CREATE OR REPLACE FUNCTION crm_nay_ligada()
RETURNS TABLE(ligada boolean, motivo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  -- a mesma leitura da caixa de saída (nai_liberar_saida): pausada é tudo que
  -- não for exatamente 'nao' -- na dúvida, vermelho
  SELECT x.modo = 'todos' AND x.pausa = 'nao',
         CASE WHEN x.pausa <> 'nao' THEN 'A Nay está pausada (PARAR ATENDIMENTO)'
              WHEN x.modo = 'teste' THEN 'A Nay está só nos testes'
              WHEN x.modo <> 'todos' THEN 'A Nay está desligada'
              ELSE NULL END
    FROM (SELECT nai_cfg('modo', 'desligado') AS modo, nai_cfg('pausada', 'sim') AS pausa) x
$$;
REVOKE ALL ON FUNCTION crm_nay_ligada() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_nay_ligada() TO nay_disparo;

COMMIT;
