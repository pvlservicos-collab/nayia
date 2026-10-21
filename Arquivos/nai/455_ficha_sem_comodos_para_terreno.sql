-- 455 -- O cadastro do imóvel novo (captacao_ficha) não pergunta cômodos nem mobília de terreno, lote, galpão, sala,
--        loja, ponto comercial, chácara ou sítio
--
-- Pedro, 21/10/2026, antes do disparo do outro_imovel_04 nas listas 3, 4 e 5: "só vê se a Nay da API oficial vai atender
-- direitinho". No ensaio, o dono disse "tenho um terreno no Tarumã pra vender" e ouviu "Quantos quartos (e quantas
-- suítes), banheiros e vagas de garagem ele tem?". O tipo vem do que ele disse (tipo) ou do começo da descrição.
-- Casa e apartamento seguem iguais.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.captacao_ficha(p_telefone text, p_qual text, p_campos jsonb, p_resposta boolean DEFAULT true)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  l        captacao_leads%ROWTYPE;
  c        captacao_cadastro%ROWTYPE;
  i        imoveis%ROWTYPE;
  v_qual   text := lower(btrim(coalesce(p_qual, '')));
  v_tipo   text;
  v_sem_comodos boolean;   -- 455: terreno, lote, galpão, sala, loja, chácara, sítio: sem cômodos nem mobília
  v_outra  text;
  v_novos  jsonb;
  v_resp   jsonb;
  v_trat   text;
  v_nome   text;
  v_pron   text;
  v_pron_m text;
  v_voc    text;
  v_aluga  boolean;
  v_cond   boolean;
  v_parar  boolean;
  v_falta  text[];
  v_prox   text;
  v_frase  text;
  d        jsonb;
BEGIN
  SELECT * INTO l FROM captacao_leads WHERE telefone_chave = nay_fone_chave(p_telefone) ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN 'nao achei este proprietario na lista. siga o roteiro normalmente e NAO diga que anotou.';
  END IF;
  -- uma ficha por vez por dono (a foto que chega pelo site usa a mesma trava)
  PERFORM pg_advisory_xact_lock(hashtext('captacao_ficha'), l.id::int);

  v_tipo := CASE WHEN v_qual ~ '(outro|nov[oa])' THEN 'novo'
                 WHEN v_qual ~ '(este|esse|mesmo|campanha|atualiz)' THEN 'atualizar'
                 ELSE coalesce((SELECT x.tipo FROM captacao_cadastro x
                                 WHERE x.lead_id = l.id AND x.estado = 'coletando'
                                 ORDER BY x.atualizado_em DESC, x.id DESC LIMIT 1), 'atualizar') END;

  -- tratamento: "Sr. João" / "o Sr." / "você"
  v_trat := NULLIF(btrim(l.tratamento), '');
  v_nome := NULLIF(nay_primeiro_nome(l.nome), '');
  v_pron := CASE v_trat WHEN 'Sra.' THEN 'a Sra.' WHEN 'Sr.' THEN 'o Sr.' ELSE 'você' END;
  v_pron_m := upper(left(v_pron, 1)) || substr(v_pron, 2);
  v_voc  := CASE WHEN v_trat IS NOT NULL THEN v_trat || coalesce(' ' || v_nome, '') ELSE v_nome END;

  -- o imóvel da campanha só tem ficha se ele disse que está disponível
  -- (quem abre é guardar_situacao, p_resposta = false, logo depois de gravar)
  IF v_tipo = 'atualizar' AND p_resposta AND coalesce(l.situacao, '') <> 'disponivel' THEN
    RETURN 'nao anotei: o imovel desta campanha nao esta registrado como disponivel, entao nao tem ficha para preencher. '
        || 'se ele falou de OUTRO imovel, chame guardar_ficha com qual = outro. senao siga o roteiro e NAO diga que anotou.';
  END IF;

  -- o que ele disse agora: só as chaves da ficha, texto limpo
  SELECT coalesce(jsonb_object_agg(k, btrim(v)), '{}'::jsonb) INTO v_novos
    FROM jsonb_each_text(coalesce(p_campos, '{}'::jsonb)) AS e(k, v)
   WHERE k IN ('tipo', 'bairro', 'condominio', 'negocio', 'quartos', 'suites', 'banheiros', 'vagas', 'area',
               'valor', 'condominio_valor', 'iptu', 'incluso', 'mobilia', 'fotos', 'detalhes')
     AND NULLIF(btrim(v), '') IS NOT NULL AND lower(btrim(v)) NOT IN ('null', 'undefined', '-');
  v_parar := p_resposta AND lower(btrim(coalesce(p_campos->>'parar', ''))) ~ '^(sim|s|true|parar|1)$';

  SELECT * INTO c FROM captacao_cadastro
   WHERE lead_id = l.id AND tipo = v_tipo AND estado = 'coletando' ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN
    -- NÃO RECOMEÇA: a ficha que já ficou pronta é a mesma ficha. Vale sempre
    -- para o imóvel da campanha; para o imóvel novo só na resposta -- abrir
    -- (guardar_outro_imovel) é outro imóvel de verdade.
    SELECT * INTO c FROM captacao_cadastro
     WHERE lead_id = l.id AND tipo = v_tipo AND estado IN ('pronto', 'aplicado')
       AND (v_tipo = 'atualizar' OR p_resposta)
       AND criado_em > now() - interval '60 days'
     ORDER BY id DESC LIMIT 1;
    IF FOUND THEN
      IF c.estado = 'pronto' AND NOT c.dados @> v_novos THEN
        UPDATE captacao_cadastro SET dados = dados || v_novos, atualizado_em = now() WHERE id = c.id;
      END IF;
      RETURN 'a ficha d' || CASE WHEN v_tipo = 'novo' THEN 'o imovel novo' ELSE 'este imovel' END || ' ja esta completa'
          || CASE WHEN c.estado = 'pronto' AND NOT c.dados @> v_novos THEN ', e anotei o que ' || v_pron || ' acrescentou' ELSE '' END
          || '. NAO pergunte de novo nada da ficha. '
          || CASE WHEN v_tipo = 'atualizar'
                  THEN 'siga o roteiro: se ainda nao perguntou, pergunte se ' || v_pron || ' tem algum outro imovel alem desse que queira vender ou alugar.'
                  ELSE 'agradeca em uma linha e chame encerrar_conversa, a menos que ' || v_pron || ' fale de mais um imovel.' END;
    END IF;
    -- 318: o imóvel dele JÁ ESTÁ no nosso cadastro -> só o valor do aluguel, sem as perguntas da ficha
    IF v_tipo = 'atualizar' AND l.codigo ~ '^\d+$' AND EXISTS (SELECT 1 FROM imoveis x WHERE x.codigo = l.codigo::int) THEN
      INSERT INTO captacao_cadastro (lead_id, tipo, codigo, estado, dados)
      VALUES (l.id, v_tipo, l.codigo::int, 'pronto', v_novos);
      RETURN 'o imovel dele ja esta no nosso cadastro'
          || CASE WHEN v_novos ? 'valor' THEN ', e o valor do aluguel ficou anotado' ELSE '' END
          || '. NAO pergunte mais nada sobre este imovel (quartos, area, condominio, IPTU, mobilia, fotos). '
          || 'siga o roteiro: se ainda nao perguntou, pergunte se ' || v_pron
          || ' tem algum outro imovel alem desse que queira vender ou alugar.';
    END IF;
    INSERT INTO captacao_cadastro (lead_id, tipo, codigo)
    VALUES (l.id, v_tipo, CASE WHEN v_tipo = 'atualizar' AND l.codigo ~ '^\d+$' THEN l.codigo::int END)
    RETURNING * INTO c;
  END IF;

  d := c.dados || v_novos;
  -- a pergunta que estava aberta conta como respondida (mesmo com "não sei"),
  -- desde que ele tenha dito ALGUMA coisa -- abrir a ficha não conta
  IF p_resposta AND v_novos <> '{}'::jsonb AND d ? '_perguntou' THEN
    v_resp := coalesce(d->'_respondidas', '[]'::jsonb);
    IF NOT v_resp ? (d->>'_perguntou') THEN
      d := jsonb_set(d, '{_respondidas}', v_resp || to_jsonb(d->>'_perguntou'));
    END IF;
  END IF;
  v_resp := coalesce(d->'_respondidas', '[]'::jsonb);

  IF c.codigo IS NOT NULL THEN
    SELECT * INTO i FROM imoveis WHERE codigo = c.codigo;
  END IF;

  v_aluga := CASE WHEN v_tipo = 'atualizar' THEN true ELSE coalesce(d->>'negocio', '') !~* 'vend' OR coalesce(d->>'negocio', '') ~* 'amb|alug|loca' END;
  v_cond  := coalesce(NULLIF(btrim(d->>'condominio'), ''), i.condominio_nome) IS NOT NULL
             OR coalesce(d->>'tipo', i.tipo, '') ~* 'apart|condom|flat|cobertura|sala';
  -- 455 (Pedro, 21/10: a Nay perguntou "quantos quartos" de um terreno): o tipo dito, ou o começo da descrição dele
  v_sem_comodos := coalesce(d->>'tipo', i.tipo, '') ~* '(terreno|lote|galp|sala|loja|comercial|ch[aá]cara|s[ií]tio)'
                   OR (coalesce(d->>'tipo', i.tipo) IS NULL
                       AND coalesce(d->>'detalhes', '') ~* '^\W*(um |uma )?(terreno|lote|galp[aã]o|sala comercial|loja|ponto comercial|ch[aá]cara|s[ií]tio)');

  -- o que ainda falta, NA ORDEM do roteiro (grupo respondido não volta)
  v_falta := ARRAY[]::text[];
  IF v_tipo = 'novo' AND NOT v_resp ? 'local' AND ((d->>'tipo' IS NULL AND NOT v_sem_comodos) OR coalesce(d->>'bairro', d->>'condominio') IS NULL) THEN
    v_falta := v_falta || 'local'::text;
  END IF;
  IF v_tipo = 'novo' AND NOT v_resp ? 'negocio' AND d->>'negocio' IS NULL THEN
    v_falta := v_falta || 'negocio'::text;
  END IF;
  IF NOT v_sem_comodos AND NOT v_resp ? 'comodos' AND (coalesce(d->>'quartos', i.quartos::text) IS NULL
                                 OR coalesce(d->>'banheiros', i.banheiros::text) IS NULL
                                 OR coalesce(d->>'vagas', i.vagas::text) IS NULL) THEN
    v_falta := v_falta || 'comodos'::text;
  END IF;
  IF NOT v_resp ? 'area' AND coalesce(d->>'area', i.area_util::text, i.area_total::text) IS NULL THEN
    v_falta := v_falta || 'area'::text;
  END IF;
  IF NOT v_resp ? 'valor' AND coalesce(d->>'valor', CASE WHEN v_tipo = 'atualizar' THEN l.valor_locacao_pedido END) IS NULL THEN
    v_falta := v_falta || 'valor'::text;
  END IF;
  IF NOT v_resp ? 'taxas' AND (d->>'iptu' IS NULL OR (v_cond AND d->>'condominio_valor' IS NULL) OR (v_aluga AND d->>'incluso' IS NULL)) THEN
    v_falta := v_falta || 'taxas'::text;
  END IF;
  IF v_aluga AND NOT v_sem_comodos AND NOT v_resp ? 'mobilia' AND coalesce(d->>'mobilia', CASE WHEN v_tipo = 'atualizar' THEN i.mobilia END) IS NULL THEN
    v_falta := v_falta || 'mobilia'::text;
  END IF;
  IF NOT v_resp ? 'fotos' AND d->>'fotos' IS NULL AND jsonb_array_length(c.fotos) = 0 THEN
    v_falta := v_falta || 'fotos'::text;
  END IF;

  -- ele não quer (ou não pode) responder mais: a ficha fecha com o que tem
  IF v_parar AND cardinality(v_falta) > 0 THEN
    d := jsonb_set(d, '{_parou}', to_jsonb(v_falta));
    v_falta := ARRAY[]::text[];
  END IF;

  v_prox := v_falta[1];
  v_frase := CASE v_prox
    WHEN 'local'   THEN 'É casa ou apartamento? E em qual bairro ou condomínio fica?'
    WHEN 'negocio' THEN v_pron_m || ' quer alugar ou vender esse imóvel?'
    WHEN 'comodos' THEN 'Quantos quartos (e quantas suítes), banheiros e vagas de garagem ele tem?'
    WHEN 'area'    THEN 'E a área, ' || v_pron || ' sabe mais ou menos quantos metros quadrados?'
    WHEN 'valor'   THEN CASE WHEN v_tipo = 'atualizar'
                              THEN coalesce(v_voc || ', ', '') || v_pron || ' pode me atualizar o valor do imóvel para locação?'
                              WHEN v_aluga AND coalesce(d->>'negocio', '') ~* 'amb'
                              THEN 'E quais valores ' || v_pron || ' quer pedir, no aluguel e na venda?'
                              -- 357: ele não disse se aluga ou vende ("ainda não decidimos"): não presume aluguel
                              WHEN coalesce(d->>'negocio', '') !~* 'vend|alug|loca|amb'
                              THEN 'E qual valor ' || v_pron || ' pensa em pedir, no aluguel ou na venda?'
                              WHEN v_aluga THEN 'E qual valor ' || v_pron || ' quer pedir no aluguel?'
                              ELSE 'E qual valor ' || v_pron || ' quer pedir na venda?' END
    WHEN 'taxas'   THEN CASE WHEN v_cond AND v_aluga AND (v_tipo = 'atualizar' OR coalesce(d->>'negocio', '') ~* 'alug|loca|amb')
                                   THEN 'E o condomínio e o IPTU, estão em quanto? O aluguel já inclui algum deles?'
                              WHEN v_aluga AND (v_tipo = 'atualizar' OR coalesce(d->>'negocio', '') ~* 'alug|loca|amb')
                                   THEN 'E o IPTU, sabe me dizer o valor? O aluguel já inclui alguma coisa, como água ou IPTU?'
                              WHEN v_cond THEN 'E o condomínio e o IPTU, estão em quanto?'
                              ELSE 'E o IPTU, sabe me dizer o valor?' END
    WHEN 'mobilia' THEN 'Ele está mobiliado, com modulados e ar, só climatizado ou sem móveis?'
    WHEN 'fotos'   THEN v_pron_m || ' pode me enviar as fotos do imóvel?'
    END;

  IF v_prox IS NULL THEN
    UPDATE captacao_cadastro SET dados = d - '_perguntou', estado = 'pronto', atualizado_em = now() WHERE id = c.id;
    -- DUAS FICHAS: ele falou do outro imóvel no meio desta -- volta para a que ficou aberta
    SELECT x.tipo INTO v_outra FROM captacao_cadastro x
     WHERE x.lead_id = l.id AND x.estado = 'coletando' AND x.id <> c.id
       AND (x.tipo = 'novo' OR coalesce(l.situacao, '') = 'disponivel')
     ORDER BY x.atualizado_em DESC, x.id DESC LIMIT 1;
    IF v_outra IS NOT NULL THEN
      RETURN 'ficha ' || CASE WHEN v_tipo = 'novo' THEN 'do imovel novo' ELSE 'deste imovel' END || ' completa. agora volte a ficha '
          || CASE WHEN v_outra = 'novo' THEN 'do outro imovel' ELSE 'do imovel da campanha' END || ' -- '
          || captacao_ficha(p_telefone, CASE WHEN v_outra = 'novo' THEN 'outro' ELSE 'este' END, '{}'::jsonb, false);
    END IF;
    RETURN CASE WHEN v_tipo = 'atualizar'
      THEN 'ficha do imovel completa (o Tel confere e aplica). agradeca em uma linha e va para a ETAPA 4: pergunte se ' || v_pron
           || ' tem algum outro imovel alem desse que queira vender ou alugar.'
      ELSE 'ficha do imovel novo completa (o Tel confere e cadastra). agradeca em uma linha e chame encerrar_conversa -- a menos que '
           || v_pron || ' fale de mais um imovel: ai chame guardar_outro_imovel de novo.' END;
  END IF;

  UPDATE captacao_cadastro SET dados = jsonb_set(d, '{_perguntou}', to_jsonb(v_prox)), atualizado_em = now() WHERE id = c.id;
  RETURN 'anotado na ficha do imovel' || CASE WHEN v_tipo = 'novo' THEN ' novo' ELSE '' END
         || '. agora pergunte isto, com estas palavras, UMA pergunta so (pode comecar com "Certo." ou "Entendi."): "'
         || v_frase || '". quando ' || v_pron || ' responder, chame guardar_ficha com o que disse'
         || ' (se nao souber ou nao quiser dizer, passe "nao sabe" no campo perguntado).';
END $function$;

COMMIT;
