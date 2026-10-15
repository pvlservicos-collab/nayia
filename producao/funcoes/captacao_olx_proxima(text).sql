CREATE OR REPLACE FUNCTION public.captacao_olx_proxima(p_telefone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  l      captacao_leads;
  o      captacao_olx;
  p      jsonb;
  a      jsonb;
  r      jsonb;
  v_loc  boolean;
  g      text;
  e      text;
  campos text[];
  c      text;
  v_tr   text;
  v_valor text;
  v_sim  boolean;
BEGIN
  SELECT * INTO l FROM captacao_leads WHERE telefone_chave = nay_fone_chave(p_telefone);
  SELECT * INTO o FROM captacao_olx WHERE lead_id = l.id;
  IF o.lead_id IS NULL THEN RETURN NULL; END IF;
  p := captacao_olx_perfil(l.id); a := o.anuncio; r := o.respostas;
  v_loc := p->>'negocio' = 'locacao'; g := p->>'grupo'; e := p->>'elevador';
  v_tr := l.tratamento;

  -- a ordem do roteiro do Pedro, por perfil
  campos := ARRAY['condominio_nome'];
  IF g = 'ap' AND e = 'desconhecido' THEN campos := array_append(campos, 'elevador'); END IF;
  IF g <> 'casa_rua' THEN campos := campos || CASE WHEN g = 'casa_cond' THEN ARRAY['metragem_terreno', 'taxa_condominio'] ELSE ARRAY['taxa_condominio'] END; END IF;
  IF v_loc THEN campos := array_append(campos, 'iptu'); END IF;
  IF g = 'ap' AND e = 'nao' THEN campos := campos || ARRAY['lances_escada', 'bloco']; END IF;
  IF g = 'ap' AND e = 'sim' THEN campos := campos || ARRAY['andar', 'torre']; END IF;
  IF g = 'casa_cond' THEN campos := array_append(campos, 'numero_casa'); END IF;
  IF g = 'casa_rua' THEN campos := ARRAY['metragem_terreno'] || CASE WHEN v_loc THEN ARRAY['iptu'] ELSE '{}'::text[] END || ARRAY['endereco']; END IF;
  IF g <> 'outro' THEN campos := array_append(campos, 'sol'); END IF;
  IF NOT v_loc THEN campos := array_append(campos, 'honorarios');
  ELSIF g <> 'casa_rua' THEN campos := array_append(campos, 'condominio_incluso'); END IF;
  campos := campos || ARRAY['outros', 'outros_detalhe', 'indicacao'];

  FOREACH c IN ARRAY campos LOOP
    CONTINUE WHEN r ? c;
    -- o que o anúncio já diz não se pergunta
    CONTINUE WHEN c = 'condominio_nome' AND (p->>'condominio' IS NOT NULL OR g = 'casa_rua');
    CONTINUE WHEN c = 'taxa_condominio' AND a ? 'taxa_condominio';
    CONTINUE WHEN c = 'iptu' AND a ? 'iptu';
    CONTINUE WHEN c = 'andar' AND a ? 'andar';
    CONTINUE WHEN c = 'lances_escada' AND (p->>'terreo')::boolean;
    CONTINUE WHEN c = 'sol' AND a ? 'sol';
    CONTINUE WHEN c = 'metragem_terreno' AND a ? 'area_total';
    CONTINUE WHEN c = 'endereco' AND a ? 'logradouro' AND a ? 'numero';
    -- o detalhe do outro imóvel só existe quando ele disse que tem
    IF c = 'outros_detalhe' THEN
      v_sim := r ? 'outros' AND lower(nay_sem_acento(r->>'outros')) !~ '^\s*(nao|no momento nao|so esse|so este|por enquanto nao|nenhum|tenho nao)';
      CONTINUE WHEN NOT v_sim;
    END IF;
    v_valor := CASE WHEN p->'valor' IS NOT NULL AND p->>'valor' <> '' THEN
                 'R$ ' || replace(to_char(round((p->>'valor')::numeric), 'FM999,999,999'), ',', '.') END;
    RETURN jsonb_build_object('campo', c, 'pergunta', CASE c
      WHEN 'condominio_nome'   THEN 'Qual é o nome do condomínio?'
      WHEN 'elevador'          THEN 'O prédio tem elevador ou é de escada?'
      WHEN 'taxa_condominio'   THEN 'Qual o valor da taxa de condomínio?'
      WHEN 'iptu'              THEN captacao_olx_pronome(v_tr, true) || ' se recorda do valor do IPTU?'
      WHEN 'lances_escada'     THEN 'Quantos lances de escada até o apartamento?'
      WHEN 'bloco'             THEN 'Qual o bloco do seu apartamento?'
      WHEN 'andar'             THEN 'Qual o andar do seu apartamento?'
      WHEN 'torre'             THEN 'Qual a torre do seu apartamento?'
      WHEN 'metragem_terreno'  THEN 'Qual a metragem do seu terreno?'
      WHEN 'numero_casa'       THEN 'Qual o número da casa?'
      WHEN 'endereco'          THEN 'Qual o endereço da casa?'
      WHEN 'sol'               THEN 'A sua sala pega o sol da manhã ou da tarde?'
      WHEN 'honorarios'        THEN CASE WHEN v_valor IS NOT NULL
                                         THEN 'No valor de ' || v_valor || ', já estão inclusos os honorários de 6% de corretagem?'
                                         ELSE 'No valor que ' || captacao_olx_pronome(v_tr, false) || ' está pedindo, já estão inclusos os honorários de 6% de corretagem?' END
      WHEN 'condominio_incluso' THEN 'No valor que ' || captacao_olx_pronome(v_tr, false) || ' está pedindo'
                                      || coalesce(', de ' || v_valor, '') || ', está inclusa a taxa de condomínio?'
      WHEN 'outros'            THEN captacao_olx_pronome(v_tr, true) || ' tem outros imóveis que queira vender ou alugar?'
      WHEN 'outros_detalhe'    THEN 'Qual é o outro imóvel e onde fica?'
      WHEN 'indicacao'         THEN 'Estamos com uma demanda alta de clientes querendo comprar imóveis nesse final de ano. '
                                    || captacao_olx_pronome(v_tr, true) || ' teria alguém para indicar que queira vender ou alugar?'
    END);
  END LOOP;
  RETURN jsonb_build_object('fim', true);
END $function$;
