-- 431 (Pedro, 20/10/2026): "será criada uma nova etapa lá no CRM, no final: Cadastrando" (cadastro de imóvel pelo
-- WhatsApp, 428). O funil da Parceria (crm_parceria_funil, lido pelo CRM a cada minuto em src/lib/funis.ts) devolve
-- 'Cadastrando' para quem a Nay do cadastro está perguntando (ficha na fila ou perguntando). Quem está em cadastro sai das
-- linhas da etapa da Nay (identificação, recebeu imóvel, agendamento): uma linha por pessoa, senão o card ia e voltava
-- a cada minuto. Quando a ficha fecha, a pessoa some daqui e o CRM devolve o card para a etapa onde estava.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.crm_parceria_funil()
 RETURNS TABLE(telefone text, lid text, etapa text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH cadastro AS (
    -- 431: quem a Nay do cadastro está perguntando (ou vai perguntar), pelo contato da ficha e as linhas irmãs dele
    SELECT DISTINCT k.id AS contato_id
      FROM privado.cadastro_whats c
      JOIN nai_contato k ON k.chave = nai_chave(c.contato_tel)
     WHERE c.estado IN ('na_fila', 'perguntando') AND c.contato_tel IS NOT NULL
  ), em_cadastro AS (
    SELECT DISTINCT i.id FROM cadastro c CROSS JOIN LATERAL unnest(coalesce(nai_contato_irmaos(c.contato_id), ARRAY[c.contato_id])) AS i(id)
  ), linhas AS (
    SELECT e.contato_id,
           CASE e.etapa WHEN 'identificacao' THEN 'Identificação'
                        WHEN 'recebeu_imovel' THEN 'Recebeu imóvel'
                        WHEN 'agendamento_visita' THEN 'Agendamento de visita' END AS etapa
      FROM nai_etapa_contato e
     WHERE e.etapa IN ('identificacao', 'recebeu_imovel', 'agendamento_visita')
       AND e.contato_id NOT IN (SELECT id FROM em_cadastro)
    UNION ALL
    SELECT c.contato_id, 'Cadastrando' FROM cadastro c
  )
  SELECT (SELECT nai_fone_br(c2.telefone) FROM nai_contato c2
           WHERE c2.id = ANY (nai_contato_irmaos(l.contato_id)) AND c2.chave !~ '^lid:' AND coalesce(c2.telefone, '') <> ''
           ORDER BY c2.id LIMIT 1),
         (SELECT regexp_replace(c3.chave, '\D', '', 'g') FROM nai_contato c3
           WHERE c3.id = ANY (nai_contato_irmaos(l.contato_id)) AND c3.chave ~ '^lid:'
           ORDER BY c3.id LIMIT 1),
         l.etapa
    FROM linhas l
$function$;

-- E o FINO ACABAMENTO no popup de cadastro do CRM (CadastroDeImovel.tsx): a leitura devolve o campo (Sim/Não/vazio)
CREATE OR REPLACE FUNCTION public.crm_imovel_para_cadastro(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'codigo', i.codigo, 'status', i.status, 'origem', i.origem,
    'tipo', i.tipo, 'bairro', i.bairro, 'condominio', i.condominio_nome, 'condoId', i.condo_id,
    'logradouro', i.logradouro, 'numero', i.numero, 'complemento', i.complemento,
    'cidade', i.cidade, 'estado', i.estado,
    'quartos', i.quartos, 'suites', i.suites, 'banheiros', i.banheiros,
    'vagas', i.vagas, 'vagasCobertas', i.vagas_cobertas,
    'areaUtil', i.area_util, 'areaTotal', i.area_total,
    'andar', i.andar, 'sol', i.sol, 'mobilia', i.mobilia,
    'taxaCondominio', i.taxa_condominio, 'iptu', i.iptu,
    'aluguel', i.valor_aluguel, 'venda', i.valor_venda,
    'caracteristicas', to_jsonb(coalesce(i.caracteristicas, '{}'::text[])),
    'descricao', i.descricao,
    'inclusoNoAluguel', i.extras->>'incluso no aluguel',
    'finoAcabamento', i.extras->>'fino acabamento',
    'temDono', i.proprietario_id IS NOT NULL,
    'dono', (SELECT p.nome FROM proprietarios p WHERE p.id = i.proprietario_id),
    'fotos', (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo),
    'pontuacao', nai_imovel_pontos(i.codigo))
    FROM imoveis i
   WHERE i.codigo = p_codigo
$function$;

COMMIT;
