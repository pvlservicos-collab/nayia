-- 495 (Pedro, 25/10): "você vai comparar a Nay Parceria, que já otimizamos e corrigimos muita coisa, e ver o que ela tem
-- que as outras Nay não têm mas poderiam, e melhoram o atendimento e a escolha de imóveis, e aplicar nas outras e salvar
-- em uma aba lá no site Agentes: vai ter uma aba embaixo, Inteligências gerais dos agentes, e vai salvar lá essas regras
-- para futuramente".
--
-- nay_inteligencia_geral: uma regra por linha, de onde veio (a Nay que já tem, ou o Tel), para quem vale (parceria,
-- leads, captacao, olx) e onde já está aplicada. A página admin › Agentes lê e grava por site_inteligencias /
-- site_inteligencia_salvar. É aqui que o "Adicionar inteligência: ..." do Tel vai morar quando entrar.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.nay_inteligencia_geral (
  id          bigserial PRIMARY KEY,
  regra       text NOT NULL,
  porque      text,
  origem      text NOT NULL DEFAULT 'parceria',     -- a Nay que já tinha (parceria, leads, captacao, olx) ou 'tel'
  vale_para   text[] NOT NULL DEFAULT ARRAY['parceria', 'leads', 'captacao', 'olx'],
  aplicada_em text[] NOT NULL DEFAULT '{}',
  assunto     text,
  ativa       boolean NOT NULL DEFAULT true,
  criada_por  text,
  criada_em   timestamptz NOT NULL DEFAULT now(),
  mudada_em   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.nay_inteligencia_geral IS
  '495: as inteligências gerais dos agentes (admin › Agentes): a regra, para quem vale e onde já está aplicada.';

CREATE OR REPLACE FUNCTION public.site_inteligencias()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.ativa DESC, i.assunto NULLS LAST, i.id), '[]'::jsonb)
    FROM nay_inteligencia_geral i
$function$;

CREATE OR REPLACE FUNCTION public.site_inteligencia_salvar(p jsonb, p_quem text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id bigint := nullif(p->>'id', '')::bigint;
  v_lista text[] := ARRAY['parceria', 'leads', 'captacao', 'olx'];
  v_vale text[] := ARRAY(SELECT x FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'vale_para') = 'array' THEN p->'vale_para' ELSE '[]' END) x WHERE x = ANY (v_lista));
  v_apl text[] := ARRAY(SELECT x FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'aplicada_em') = 'array' THEN p->'aplicada_em' ELSE '[]' END) x WHERE x = ANY (v_lista));
BEGIN
  IF btrim(coalesce(p->>'regra', '')) = '' THEN RAISE EXCEPTION 'a regra está vazia'; END IF;
  IF v_id IS NULL THEN
    INSERT INTO nay_inteligencia_geral (regra, porque, origem, vale_para, aplicada_em, assunto, ativa, criada_por)
    VALUES (btrim(p->>'regra'), nullif(btrim(coalesce(p->>'porque', '')), ''), coalesce(nullif(p->>'origem', ''), 'tel'),
            CASE WHEN cardinality(v_vale) > 0 THEN v_vale ELSE v_lista END, v_apl,
            nullif(btrim(coalesce(p->>'assunto', '')), ''), coalesce((p->>'ativa')::boolean, true), left(p_quem, 80))
    RETURNING id INTO v_id;
  ELSE
    UPDATE nay_inteligencia_geral
       SET regra = btrim(p->>'regra'), porque = nullif(btrim(coalesce(p->>'porque', '')), ''),
           vale_para = CASE WHEN cardinality(v_vale) > 0 THEN v_vale ELSE vale_para END, aplicada_em = v_apl,
           assunto = nullif(btrim(coalesce(p->>'assunto', '')), ''), ativa = coalesce((p->>'ativa')::boolean, ativa),
           mudada_em = now()
     WHERE id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'não achei a inteligência %', v_id; END IF;
  END IF;
  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.site_inteligencias() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_inteligencia_salvar(jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_inteligencias() TO nay, nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_inteligencia_salvar(jsonb, text) TO nay, nay_site_escrita;
GRANT SELECT ON public.nay_inteligencia_geral TO nay_leitura;

-- A comparação de 25/10: o que a Nay Parceria (nay-core) já faz e as outras ainda não, ou fazem diferente.
-- aplicada_em diz onde já vale hoje (conferido no código de 25/10).
INSERT INTO nay_inteligencia_geral (regra, porque, origem, vale_para, aplicada_em, assunto, criada_por) VALUES
 ('"Manda o que você tem" fecha os filtros: o que falta vira "tanto faz" e as opções saem.',
  'Na Parceria (manda_o_que_tem) o pedido não fica preso em pergunta; a Nay Leads pergunta o roteiro inteiro.',
  'parceria', ARRAY['parceria','leads'], ARRAY['parceria'], 'filtros', 'comparação 25/10'),
 ('Pergunta de filtro que ficou sem resposta sai uma vez só; sem resposta, vira "tanto faz" e a busca segue.',
  'Parceria, 20/10 (pergunta-de-filtro-sai-uma-vez). A Nay Leads só segura a repetição, mas espera a resposta.',
  'parceria', ARRAY['parceria','leads'], ARRAY['parceria'], 'filtros', 'comparação 25/10'),
 ('Conjunto e avenida viram os bairros pela biblioteca de regiões do Tel, não pelo que o modelo acha.',
  'Parceria: conjunto_e_avenida_viram_bairro. A Nay Leads deixa o modelo traduzir "da Constantino Nery até a Ponta Negra".',
  'parceria', ARRAY['parceria','leads'], ARRAY['parceria'], 'lugar', 'comparação 25/10'),
 ('Nome de condomínio escrito de ouvido resolve ("Piazza dell acqua", "laranjeiras"); ambíguo ou nome de bairro, pergunta qual.',
  'Parceria: condominio_de_ouvido e nome_pela_metade. A Nay Leads tem o condomínio sem acento desde 21/10, sem o pedaço do nome.',
  'parceria', ARRAY['parceria','leads','captacao'], ARRAY['parceria'], 'lugar', 'comparação 25/10'),
 ('"Tá valendo?", "compensa?": "Está valendo, sim! Está disponível por R$ X." e o card. Não é dúvida para a equipe.',
  'Parceria: ta_valendo. Na Nay Leads a pergunta pode virar "perguntar" e ir à fila.',
  'parceria', ARRAY['parceria','leads','olx'], ARRAY['parceria'], 'dúvidas', 'comparação 25/10'),
 ('Energia é do locatário: quem aluga paga o consumo; só a energia solar do imóvel não entra nessa regra.',
  'Parceria, 22/10 (core 992c906). A Nay Leads responde pela ficha e pode dizer que "não sabe".',
  'parceria', ARRAY['parceria','leads'], ARRAY['parceria'], 'dúvidas', 'comparação 25/10'),
 ('Andar: com escada, os lances; com elevador, o andar; prédio com mais de 10 andares, só baixo, médio ou alto. "Andar alto" dito pelo corretor vale.',
  'Parceria: andar_de_predio_alto e andar em faixa (23/10).',
  'parceria', ARRAY['parceria','leads','olx'], ARRAY['parceria'], 'dúvidas', 'comparação 25/10'),
 ('A mobília vem do cadastro antes do anúncio antigo: o que a equipe corrigiu no cadastro vale.',
  'Parceria, 0030f2c (o 2944 respondia "modulados e ar" sendo mobiliado). A busca da Nay Leads já usa o cadastro (core_imovel_busca).',
  'parceria', ARRAY['parceria','leads'], ARRAY['parceria','leads'], 'imóveis', 'comparação 25/10'),
 ('Faixa de valor firme: do teto dito, de 20 a 25% abaixo até 10% acima; fora disso, mais longe na mesma faixa, nunca mais caro.',
  'Parceria: valor_25_abaixo_10_acima e a_faixa_manda_mais_longe. A Nay Leads usa 20% abaixo e 10% acima (olx_cliente_buscar).',
  'parceria', ARRAY['parceria','leads'], ARRAY['parceria','leads'], 'imóveis', 'comparação 25/10'),
 ('Proprietário é sagrado: a Nay não atende dono; só pergunta por visita, fechamento ou dúvida, chamando pelo nome do cadastro, nunca por sigla.',
  'Parceria, 463. A Nay Leads fala com o dono pela linha certa desde a 492.',
  'parceria', ARRAY['parceria','leads','captacao','olx'], ARRAY['parceria','leads'], 'pessoas', 'comparação 25/10'),
 ('Nunca dizer "parceria/parceiro/outra imobiliária" de um imóvel; para o cliente todo imóvel é da Imob Easy.',
  'Parceria: parceria_nunca (parede do validador). Na Nay Leads está no prompt, sem parede que barre o texto.',
  'parceria', ARRAY['parceria','leads','olx'], ARRAY['parceria'], 'voz', 'comparação 25/10'),
 ('Código, valor e foto só do que a ferramenta do turno trouxe: o texto não inventa código, R$ nem foto.',
  'Parceria: codigo_so_de_ferramenta, valor_so_de_ferramenta, foto_so_do_imovel (paredes). A Nay Leads confia no modelo.',
  'parceria', ARRAY['parceria','leads'], ARRAY['parceria'], 'voz', 'comparação 25/10'),
 ('Na escalada, o grupo da equipe recebe o que a pessoa mandou e o número, e alguém assume.',
  'Pedro, 24/10: valia na Nay Leads (9981496); na Parceria desde 25/10 (nay-core 326dcb8).',
  'leads', ARRAY['parceria','leads'], ARRAY['parceria','leads'], 'equipe', 'comparação 25/10');

COMMIT;
