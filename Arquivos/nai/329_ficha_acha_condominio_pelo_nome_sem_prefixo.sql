-- 329 -- A ficha preparada (327) acha o condomínio também sem "Condomínio / Residencial / Edifício" no nome
--
-- Pedro, 09/10/2026 (Cadastro rápido, "+ Condomínio"): o dono diz "Reserva Morada" e o cadastro tem "Condomínio
-- Residencial Reserva Morada" (#360). Pelo nome exato não batia, e a tela mandava cadastrar um condomínio que já existe.
-- Agora: primeiro o nome exato; senão, o nome sem esses prefixos/sufixos, se der UM só condomínio.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.condominio_nome_nucleo(p_nome text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT nullif(btrim(regexp_replace(lower(nay_sem_acento(coalesce(p_nome, ''))),
           '^((condominio|residencial|edificio|cond\.?|res\.?|ed\.?)\s+)+|(\s+(residencial|condominio))+$', '', 'g')), '');
$function$;

CREATE OR REPLACE FUNCTION public.site_ficha_preparada(p_ficha bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH b AS (
    SELECT c.*, a.campos, a.observacao, a.pronto, a.duplicado_de, a.analisado_em,
           nullif(btrim(coalesce(a.campos->>'condominio', c.dados->>'condominio')), '') AS condo_dito,
           l.nome AS dono_nome, l.telefone AS dono_tel, l.tratamento AS dono_trat
      FROM captacao_cadastro c
      LEFT JOIN captacao_ficha_campos a ON a.ficha_id = c.id
      LEFT JOIN captacao_leads l ON l.id = c.lead_id
     WHERE c.id = p_ficha
  )
  SELECT jsonb_build_object(
    'ficha', b.id, 'estado', b.estado, 'dados', b.dados,
    'campos', b.campos, 'observacao', b.observacao, 'pronto', b.pronto, 'duplicado_de', b.duplicado_de,
    'analisado_em', b.analisado_em,
    'fotos', coalesce((SELECT jsonb_agg(t.u ORDER BY t.o) FROM jsonb_array_elements_text(
                         CASE WHEN jsonb_typeof(b.fotos) = 'array' THEN b.fotos ELSE '[]'::jsonb END) WITH ORDINALITY t(u, o)
                        WHERE t.u ~ '^https?://'), '[]'::jsonb),
    'condominio', coalesce(
       (SELECT jsonb_build_object('id', co.id, 'nome', co.nome, 'bairro', co.bairro) FROM condominios co
         WHERE b.condo_dito IS NOT NULL AND lower(nay_sem_acento(co.nome)) = lower(nay_sem_acento(b.condo_dito)) LIMIT 1),
       (SELECT jsonb_build_object('id', min(co.id), 'nome', min(co.nome), 'bairro', min(co.bairro)) FROM condominios co
         WHERE b.condo_dito IS NOT NULL AND length(condominio_nome_nucleo(b.condo_dito)) >= 4
           AND condominio_nome_nucleo(co.nome) = condominio_nome_nucleo(b.condo_dito)
        HAVING count(*) = 1)),
    'dono', jsonb_build_object('nome', b.dono_nome, 'telefone', b.dono_tel, 'tratamento', b.dono_trat))
    FROM b;
$function$;
GRANT EXECUTE ON FUNCTION public.site_ficha_preparada(bigint) TO nay_site_escrita;

COMMIT;
