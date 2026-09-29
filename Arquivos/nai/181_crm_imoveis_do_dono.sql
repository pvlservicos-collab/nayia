-- 181 -- os imóveis do proprietário da captação, para o card do CRM (Pedro,
-- 29/09/2026: "o imóvel do cara já deve aparecer lá, e dar opção de atualizar,
-- e embaixo cadastrar imóvel").
--
-- De quem é: o código da campanha, os de imoveis_prop (o dono com mais de um),
-- e os ligados ao proprietario_id dele no catálogo e no imovel_privado. A ficha
-- aberta da conversa (o que ele contou e as fotos que o site guardou) vem junto,
-- para o card dizer o que o "Atualizar"/"Cadastrar" vai levar.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION crm_captacao_imoveis_do_dono(p_captacao bigint)
RETURNS TABLE(codigo int, condominio text, tipo text, bairro text, status text, disponivel boolean,
              e_parceiro boolean, valor_aluguel numeric, valor_venda numeric, capa text, fotos int,
              da_campanha boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH l AS (SELECT * FROM captacao_leads WHERE id = p_captacao),
  cods AS (
    SELECT btrim(l.codigo)::int AS codigo, true AS campanha FROM l WHERE btrim(coalesce(l.codigo, '')) ~ '^[0-9]{1,6}$'
    UNION
    SELECT btrim(x->>'codigo')::int, false FROM l, jsonb_array_elements(CASE WHEN jsonb_typeof(l.imoveis_prop) = 'array' THEN l.imoveis_prop ELSE '[]'::jsonb END) x
     WHERE btrim(coalesce(x->>'codigo', '')) ~ '^[0-9]{1,6}$'
    UNION
    SELECT i.codigo, false FROM l JOIN imoveis i ON i.proprietario_id = l.proprietario_id WHERE l.proprietario_id IS NOT NULL
    UNION
    SELECT p.codigo, false FROM l JOIN imovel_privado p ON p.proprietario_id = l.proprietario_id WHERE l.proprietario_id IS NOT NULL
  )
  SELECT i.codigo, nullif(btrim(i.condominio_nome), ''), i.tipo, i.bairro, i.status, i.disponivel,
         coalesce(i.e_parceiro, false), i.valor_aluguel, i.valor_venda,
         (SELECT f.url FROM imovel_fotos f WHERE f.codigo = i.codigo ORDER BY f.e_capa DESC NULLS LAST, f.ordem LIMIT 1),
         (SELECT count(*)::int FROM imovel_fotos f WHERE f.codigo = i.codigo),
         bool_or(c.campanha)
    FROM (SELECT codigo, bool_or(campanha) AS campanha FROM cods GROUP BY codigo) c
    JOIN imoveis i ON i.codigo = c.codigo
   GROUP BY i.codigo
   ORDER BY bool_or(c.campanha) DESC, i.codigo
   LIMIT 20
$$;

CREATE OR REPLACE FUNCTION crm_captacao_ficha_do_dono(p_captacao bigint)
RETURNS TABLE(ficha_id bigint, tipo text, codigo int, estado text, dados jsonb, fotos int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  SELECT c.id, c.tipo, c.codigo, c.estado, c.dados - '_fotos_ids',
         coalesce(jsonb_array_length(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos END), 0)
    FROM captacao_cadastro c
   WHERE c.lead_id = p_captacao AND c.estado IN ('coletando', 'pronto')
   ORDER BY (c.estado = 'pronto') DESC, c.atualizado_em DESC
   LIMIT 1
$$;

REVOKE ALL ON FUNCTION crm_captacao_imoveis_do_dono(bigint), crm_captacao_ficha_do_dono(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_captacao_imoveis_do_dono(bigint), crm_captacao_ficha_do_dono(bigint) TO nay_disparo;

COMMIT;
