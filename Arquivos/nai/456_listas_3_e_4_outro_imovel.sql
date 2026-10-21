-- 456 -- As listas 4 (donos que só têm imóvel vendido) e 3 (donos com imóvel removido ou arquivado) entram na fila do
--        outro_imovel_04, e a barrinha do disparo do CRM mostra as duas
--
-- Pedro, 21/10/2026: "vou disparar ... Donos que só têm imóvel vendido (974) e Donos com imóvel removido ou arquivado
-- (591): mandar se tem algum imóvel para adicionar, estamos com uma demanda alta de imóveis e queremos saber se você tem
-- imóveis para vender". O roteiro é o ACRESCIMO_OUTRO_VENDER do nay-captacao (campanha vendido/removido, 454).
-- As exclusões são as da 447 (60 dias por qualquer número, nas duas direções; quem já está na captação; corretor e
-- parceiro; as fontes que privado.falou_conosco não lê).
-- Ordem (Pedro, 21/10: "pode disparar, primeiro as listas menores 1 por minuto"): a fila vai por id, então a lista 5 (163,
-- já na fila) sai primeiro, depois a 3 (589) e por último a 4 (974); a barrinha do CRM segue a mesma ordem. O ritmo vira
-- 55 a 65 s entre um modelo e outro.
BEGIN;
SET LOCAL lock_timeout = '3s';

DROP TABLE IF EXISTS _entram;
CREATE TEMP TABLE _entram ON COMMIT DROP AS
WITH corretor AS MATERIALIZED (
    SELECT nay_fone_chave(nay_fone_com_ddi(c.telefone)) AS chave FROM corretores c WHERE coalesce(c.telefone, '') <> ''
    UNION
    SELECT nay_fone_chave(nay_fone_com_ddi(p.telefone)) FROM proprietarios_export p WHERE coalesce(p.corretor, '') ~* 'parceir'
), dono AS MATERIALIZED (
    SELECT nay_fone_chave(nay_fone_com_ddi(ps.telefone)) AS chave,
           -- o imóvel citado é o de MAIOR código (o mais recente) do dono; as listas são as de site_publicos_disparo
           (array_agg(ps.id ORDER BY v.codigo DESC))[1] AS proprietario_id,
           (array_agg(ps.nome ORDER BY v.codigo DESC))[1] AS nome,
           (array_agg(nay_fone_com_ddi(ps.telefone) ORDER BY v.codigo DESC))[1] AS telefone,
           bool_and(v.status = 'Vendido') AS so_vendido, bool_and(v.status IN ('Removido', 'Arquivado')) AS so_fora,
           (array_agg(v.codigo ORDER BY v.codigo DESC))[1] AS codigo,
           (array_agg(v.condominio ORDER BY v.codigo DESC))[1] AS condominio,
           (array_agg(v.bairro ORDER BY v.codigo DESC))[1] AS bairro,
           (array_agg(v.tipo ORDER BY v.codigo DESC))[1] AS tipo,
           jsonb_agg(jsonb_build_object('codigo', v.codigo, 'condominio', v.condominio, 'endereco', v.endereco) ORDER BY v.codigo) AS imoveis_prop
      FROM vw_proprietarios_site ps JOIN vw_imoveis_todos v ON v.proprietario_id = ps.id
     WHERE length(regexp_replace(coalesce(ps.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13 AND NOT site_nao_e_dono(ps.nome)
       AND NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = nay_fone_chave(nay_fone_com_ddi(ps.telefone)))
     GROUP BY 1
), extra AS MATERIALIZED (   -- as fontes de conversa que privado.falou_conosco não lê (60 dias, 8 finais)
    SELECT right(regexp_replace(m.chave, '\D', '', 'g'), 8) AS f8 FROM core_mensagem m
     WHERE m.chave !~ '@' AND m.recebida_em > now() - interval '60 days'
    UNION SELECT right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8) FROM mensagem_saida m
     WHERE m.enviado_em > now() - interval '60 days' AND coalesce(m.telefone, '') !~ '@'
    UNION SELECT right(regexp_replace(coalesce(s.telefone, ''), '\D', '', 'g'), 8) FROM saida_do_sistema s
     WHERE s.em > now() - interval '60 days' AND coalesce(s.telefone, '') !~ '@'
    UNION SELECT right(regexp_replace(o.telefone, '\D', '', 'g'), 8) FROM privado.olx_lead_whatsapp o
     WHERE o.atualizado_em > now() - interval '60 days'
), marcado AS (
    SELECT d.*, CASE WHEN d.so_vendido THEN 'vendido' ELSE 'removido' END AS campanha,
           nay_tratamento_por_nome(d.nome) AS tratamento,
           CASE WHEN coalesce(btrim(d.condominio), '') NOT IN ('', '—', '-') AND d.condominio !~* 'n[aã]o identificad' THEN 'no ' || btrim(d.condominio)
                WHEN coalesce(btrim(d.bairro), '') <> '' THEN 'no bairro ' || btrim(d.bairro) END AS imovel_desc
      FROM dono d WHERE d.so_vendido OR d.so_fora
)
SELECT m.* FROM marcado m
 WHERE m.telefone ~ '^[0-9]{12,13}$'
   AND coalesce(btrim(m.nome), '') <> ''
   AND NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = m.chave OR l.telefone = m.telefone)
   AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = m.chave)
   AND NOT (m.nome ~* 'corretor|corretora|parceir|broker|assessoria|imobili[aá]ri|im[oó]veis|ltda|eireli|construtor|empreendiment'
            OR nai_dono_e_parceiro(m.nome))
   AND NOT EXISTS (SELECT 1 FROM corretores k
                    WHERE right(regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 8) = right(m.telefone, 8))
   AND NOT nay_falou_conosco(m.chave, 60)
   AND NOT nay_e_corretor_chave(m.chave)
   AND NOT EXISTS (SELECT 1 FROM extra e WHERE e.f8 = right(m.telefone, 8))
   AND NOT EXISTS (SELECT 1 FROM captacao_leads o WHERE o.proprietario_id = m.proprietario_id
                                                    AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL));

INSERT INTO captacao_leads (telefone, nome, tratamento, proprietario_id, codigo, imovel_desc, condominio, bairro, tipo_imovel,
                            lista_id, quem_importou, status, etapa, pergunta_pendente, imoveis_prop, modelo_abertura, campanha)
SELECT e.telefone, e.nome, e.tratamento, e.proprietario_id, e.codigo::text, e.imovel_desc, e.condominio, e.bairro, e.tipo,
       NULL, CASE e.campanha WHEN 'vendido' THEN 'Pedro (lista 4: donos que só têm imóvel vendido, outro_imovel_04, 21/10)'
                             ELSE 'Pedro (lista 3: donos com imóvel removido ou arquivado, outro_imovel_04, 21/10)' END,
       'novo', 'aguardando_outros', 'tem outro imóvel disponível além do que já consta conosco?', e.imoveis_prop,
       'outro_imovel_04', e.campanha
  FROM _entram e
 ORDER BY (e.campanha = 'vendido'), e.proprietario_id   -- Pedro: "primeiro as listas menores" (a 3, com 589, antes da 4)
ON CONFLICT DO NOTHING;

-- Pedro, 21/10: "1 por minuto" (era 25 a 35 s: 2 por minuto)
UPDATE captacao_config SET valor = '55' WHERE chave = 'python_disparo_seg_min';
UPDATE captacao_config SET valor = '65' WHERE chave = 'python_disparo_seg_max';

-- a regra da campanha (308: corretor, nome de corretor/imobiliária, imóvel de parceiro...) é por lead: quem ela barra sai agora
DELETE FROM captacao_leads l
 WHERE l.quem_importou LIKE 'Pedro (lista _: donos %, outro_imovel_04, 21/10)' AND captacao_fora_da_campanha(l.id) IS NOT NULL;

CREATE OR REPLACE FUNCTION public.crm_captacao_disparo_oficial()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH da_lista AS (       -- de qual lista é cada lead
    SELECT l.id,
           CASE WHEN EXISTS (SELECT 1 FROM captacao_retomada_oficial r WHERE r.lead_id = l.id) THEN 'retomada'
                WHEN l.quem_importou LIKE 'Pedro (lista 5:%' THEN 'lista5'   -- 449
                WHEN l.quem_importou LIKE 'Pedro (lista 4:%' THEN 'lista4'   -- 456
                WHEN l.quem_importou LIKE 'Pedro (lista 3:%' THEN 'lista3'   -- 456
                WHEN l.quem_importou LIKE 'Pedro (lista 6:%' THEN 'lista6'
                WHEN l.quem_importou LIKE 'Pedro (lista 8:%' THEN 'lista8'
                ELSE 'anterior' END AS lista
      FROM captacao_leads l
  ), fila AS MATERIALIZED (
    SELECT d.lista, f.id FROM captacao_py_fila_do_disparo() f(id) JOIN da_lista d ON d.id = f.id
  ), esperando AS (        -- 449: na fila, mas o modelo próprio dele ainda não foi aprovado pela Meta
    SELECT d.lista, l.modelo_abertura
      FROM captacao_leads l JOIN da_lista d ON d.id = l.id
     WHERE l.modelo_abertura IS NOT NULL AND l.status = 'novo' AND l.ultimo_envio_em IS NULL
       AND NOT l.opt_out AND l.humano_assumiu_em IS NULL
       AND NOT l.modelo_abertura = ANY (regexp_split_to_array(
             coalesce((SELECT c.valor FROM captacao_config c WHERE c.chave = 'python_modelos_aprovados'), ''), '\s*,\s*'))
  ), saiu AS (
    -- quem já recebeu o modelo oficial do disparo (o lead entra em captacao_motor ao receber)
    SELECT d.lista
      FROM captacao_motor mt JOIN da_lista d ON d.id = mt.lead_id
     WHERE EXISTS (SELECT 1 FROM captacao_mensagens m
                    WHERE m.lead_id = mt.lead_id AND m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou')
  ), hoje AS (
    SELECT count(*) FILTER (WHERE m.status <> 'Falhou') AS ok, count(*) FILTER (WHERE m.status = 'Falhou') AS falhou,
           max(m.criada_em) AS ultimo
      FROM captacao_mensagens m JOIN captacao_motor mt ON mt.lead_id = m.lead_id
     WHERE m.direcao = 'enviada' AND m.origem = 'disparo'
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date
  ), ritmo AS (
    SELECT coalesce((SELECT nullif(btrim(valor), '')::numeric FROM captacao_config WHERE chave = 'python_disparo_seg_min'), 45) AS menor,
           coalesce((SELECT nullif(btrim(valor), '')::numeric FROM captacao_config WHERE chave = 'python_disparo_seg_max'), 75) AS maior
  ), m AS (
    -- 449: sem ninguém pronto na fila e com gente esperando a aprovação do modelo, o motivo é a Meta
    SELECT coalesce(captacao_py_disparo_motivo(),
                    CASE WHEN NOT EXISTS (SELECT 1 FROM fila) AND EXISTS (SELECT 1 FROM esperando)
                         THEN 'esperando a Meta aprovar o modelo ' || (SELECT string_agg(DISTINCT e.modelo_abertura, ', ') FROM esperando e) END) AS motivo
  ), nomes AS (SELECT * FROM (VALUES
      (-1, 'lista4', 'Donos que só têm imóvel vendido', 'Lista 4: donos que só têm imóvel vendido, modelo outro_imovel_04 (imóvel para vender), entraram em 21/10'),
      (-2, 'lista3', 'Donos com imóvel removido ou arquivado', 'Lista 3: donos com imóvel removido ou arquivado, modelo outro_imovel_04 (imóvel para vender), entraram em 21/10'),
      (-3, 'lista5', 'Donos com imóvel alugado', 'Lista 5: donos com imóvel alugado por nós, modelo outro_imovel_04 ("possui outro imóvel disponível?"), entraram em 20/10'),
      (1, 'lista6', 'Donos com imóvel disponível', 'Lista 6: donos com imóvel disponível no cadastro (entraram em 12/10)'),
      (2, 'lista8', 'Donos da planilha antiga', 'Lista 8: donos da planilha antiga que nunca viraram imóvel (entraram em 12/10)'),
      (3, 'anterior', 'Campanha anterior', 'Proprietários das listas de antes de 12/10 que nunca receberam nada nosso'),
      (4, 'retomada', 'Não responderam no outro número',
          'Receberam a abertura pela Z-API, nunca responderam, e recebem o modelo oficial uma vez (323)')
    ) AS v(ordem, chave, rotulo, titulo))
  SELECT jsonb_build_object(
    'ligado', coalesce((SELECT valor FROM captacao_config WHERE chave = 'python_disparo'), 'nao') = 'sim',
    'motivo', (SELECT motivo FROM m),
    -- fora do horário: o próximo minuto em que o disparo pode sair (almoço, noite, fim de semana)
    'volta_em', CASE WHEN (SELECT motivo FROM m) = 'fora do horário' THEN
                  (SELECT min(t) FROM generate_series(date_trunc('minute', now()) + interval '1 minute',
                                                      now() + interval '3 days', interval '1 minute') t
                    WHERE captacao_no_horario(t)) END,
    'hoje', (SELECT ok FROM hoje), 'falharam_hoje', (SELECT falhou FROM hoje), 'ultimo_em', (SELECT ultimo FROM hoje),
    'seg_medio', (SELECT (menor + maior) / 2 FROM ritmo),
    'listas', (SELECT jsonb_agg(jsonb_build_object(
                        'chave', n.chave, 'rotulo', n.rotulo, 'titulo', n.titulo,
                        'enviados', (SELECT count(*) FROM saiu s WHERE s.lista = n.chave),
                        'faltam', (SELECT count(*) FROM fila f WHERE f.lista = n.chave)
                                  + (SELECT count(*) FROM esperando e WHERE e.lista = n.chave),
                        'esperando', (SELECT count(*) FROM esperando e WHERE e.lista = n.chave)) ORDER BY n.ordem)
                 FROM nomes n));
$function$;

COMMIT;
