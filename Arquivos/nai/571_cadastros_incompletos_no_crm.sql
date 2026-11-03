-- 571: CRM > "+ Mais" > Cadastros incompletos (Pedro, 03/11/2026): os donos com quem a conversa do cadastro do imóvel parou
-- (captacao_cadastro em 'coletando'), com a nota do imóvel pela procura dos nossos clientes e a conferência de que NÃO se
-- fala de novo com quem já falamos em outro número ou já teve o imóvel cadastrado ("você só não viu").
--
--  privado.cadastro_incompleto_nota   a nota (0-100) de cada cadastro, calculada por nay-grupos/scripts/nota_cadastros.py
--                                     com a mesma conta dos pedidos dos grupos (grupos.pontuar) + as buscas dos clientes
--  crm_cadastros_incompletos()        o que a página lê (o CRM chama como nay_disparo: só EXECUTA função)
--
-- A conferência "falamos em outro número" que olha o CRM (as outras linhas do mesmo telefone) fica na rota do CRM
-- (crmdb); aqui ficam as do banco da Nay: caixa da Parceria, Nay do cadastro (cadastro_whats), cadastros já aplicados e
-- imóveis já cadastrados em nome do mesmo telefone.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS privado.cadastro_incompleto_nota (
  cadastro_id  bigint PRIMARY KEY,
  nota         integer NOT NULL CHECK (nota BETWEEN 0 AND 100),
  pedidos_90   integer NOT NULL DEFAULT 0,
  pedidos_70   integer NOT NULL DEFAULT 0,
  clientes     integer NOT NULL DEFAULT 0,
  melhor       jsonb,
  calculada_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.cadastro_incompleto_nota IS
  '571: a nota do imóvel de cada cadastro incompleto (captacao_cadastro coletando) pela procura: pedidos dos grupos (30 dias, nota 90+ e 70+) e buscas de clientes nossos. Gravada por nay-grupos/scripts/nota_cadastros.py.';

CREATE OR REPLACE FUNCTION public.crm_cadastros_incompletos(p_dias_fala integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.nota DESC NULLS LAST, x.atualizado_em DESC), '[]'::jsonb)
  FROM (
    SELECT c.id AS cadastro_id, c.tipo, c.codigo, c.dados, jsonb_array_length(c.fotos) AS fotos,
           c.criado_em, c.atualizado_em,
           l.id AS lead_id, l.nome, l.telefone, l.canal, l.perfil_nay, l.status, l.etapa, l.opt_out,
           (l.humano_assumiu_em IS NOT NULL) AS humano, l.humano_motivo,
           n.nota, n.pedidos_90, n.pedidos_70, n.clientes, n.melhor, n.calculada_em,
           -- o imóvel JÁ foi cadastrado: cadastro aplicado, Nay do cadastro concluída ou imóvel novo no nome do mesmo telefone
           (SELECT jsonb_agg(DISTINCT jsonb_build_object('codigo', y.codigo, 'como', y.como)) FROM (
              SELECT a.codigo, 'cadastro aplicado no painel' AS como FROM captacao_cadastro a
               WHERE a.lead_id = c.lead_id AND a.id <> c.id AND a.estado = 'aplicado' AND a.codigo IS NOT NULL
              UNION ALL
              SELECT w.codigo, 'cadastrado pela Nay do cadastro (' || w.canal || ')' FROM privado.cadastro_whats w
               WHERE w.estado = 'concluido' AND w.codigo IS NOT NULL
                 AND right(regexp_replace(coalesce(w.contato_tel, ''), '\D', '', 'g'), 8) = right(l.telefone, 8)
              UNION ALL
              SELECT i.codigo, 'imóvel novo no nome do mesmo telefone' FROM imoveis i JOIN proprietarios p ON p.id = i.proprietario_id
               WHERE c.tipo = 'novo' AND i.criado_em >= c.criado_em - interval '2 days'
                 AND right(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g'), 8) = right(l.telefone, 8)
           ) y) AS ja_cadastrado,
           -- já falamos com ele em OUTRO número (caixa da Parceria) ou a Nay do cadastro está perguntando a ele agora
           (SELECT jsonb_build_object('quando', max(m.criada_em), 'mensagens', count(*), 'linha', 'Parceria')
              FROM mensagens m
             WHERE right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8) = right(l.telefone, 8)
               AND m.criada_em > now() - make_interval(days => p_dias_fala)
            HAVING count(*) > 0) AS falou_parceria,
           (SELECT jsonb_build_object('id', w.id, 'estado', w.estado, 'canal', w.canal, 'em', w.atualizado_em)
              FROM privado.cadastro_whats w
             WHERE w.estado NOT IN ('concluido', 'cancelado')
               AND right(regexp_replace(coalesce(w.contato_tel, ''), '\D', '', 'g'), 8) = right(l.telefone, 8)
             ORDER BY w.atualizado_em DESC LIMIT 1) AS cadastro_whats_aberto
      FROM captacao_cadastro c
      JOIN captacao_leads l ON l.id = c.lead_id
      LEFT JOIN privado.cadastro_incompleto_nota n ON n.cadastro_id = c.id
     WHERE c.estado = 'coletando'
  ) x
$function$;

GRANT EXECUTE ON FUNCTION public.crm_cadastros_incompletos(integer) TO nay_disparo, nay;
COMMIT;
