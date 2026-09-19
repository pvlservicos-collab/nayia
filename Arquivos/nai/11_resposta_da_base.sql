-- =====================================================================
-- NAI -- 11: responder pela BASE antes de escalar (13/09/2026)
--
-- O que o Tel viu: perguntou "olá o imovel é mobiliado?" (4159) e a Nay
-- escalou. Pediu: "quero que a nay interprete uma grande gama de perguntas que
-- sao as mais comuns antes de escalar, mesmo que elas sejam perguntadas de
-- outras formas".
--
-- O que era: a IA chamou `o_que_sei_do_imovel`, que so conhece o que o TEL ja
-- respondeu antes (imovel_conhecimento) e nao olha a ficha; veio "nao sei" e a
-- descricao da ferramenta mandava escalar. (No 4159 especificamente a mobilia
-- nao esta em lugar nenhum: nem na tabela nem no anuncio do site.)
--
-- O que segura: `nai_resposta_da_base` le a ficha para as perguntas comuns,
-- com sinonimos, e roda ANTES de toda escalada de duvida. Sem o dado, devolve
-- NULL -- nunca afirma o que o cadastro nao diz.
--
-- O FORMATO e do Tel (13/09, depois de ler a primeira versao): "nao e
-- profissional... ela deve responder uma afirmacao formal 'Sim! E mobiliado',
-- depois listar 'Tem ...' e ai mandar em uma outra mensagem a sugestao, nao
-- tudo junto resumido". E sem emoji. A sugestao de visita sai como mensagem
-- SEPARADA, montada no 05.
-- =====================================================================

INSERT INTO nai_config (chave, valor, descricao)
VALUES ('escala_sem_parar', '5596991712835',
        'Numeros (separados por virgula) em que a NAI escala ao Tel mas NAO para o chat. Tel, 13/09: so o numero de teste.')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION nai_resposta_da_base(p_codigo int, p_pergunta text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  i      imoveis;
  q      text := lower(unaccent(coalesce(p_pergunta, '')));
  car    text;
  des    text;
  dorig  text;
  r      text[] := '{}';   -- a resposta: o primeiro e a afirmacao, o resto vira lista
  linhas text[] := '{}';
  v_fr   text;
  v_inc  text;
  v_out  text;
  f_q    text;             -- a ficha, que sai listada depois da afirmacao
  f_b    text;
  f_v    text;
  f_a    text;
  f_an   text;
  busca  text[] := ARRAY['piscina', 'academia', 'elevador', 'portaria', 'churrasqueira', 'salao de festa', 'playground',
                         'varanda', 'sacada', 'gourmet', 'ar-condicionado', 'ar condicionado', 'area de lazer', 'quadra',
                         'sauna', 'quintal', 'jardim', 'interfone', 'cerca eletrica', 'seguranca 24'];
  exibe  text[] := ARRAY['piscina', 'academia', 'elevador', 'portaria', 'churrasqueira', 'salão de festas', 'playground',
                         'varanda', 'sacada', 'espaço gourmet', 'ar-condicionado', 'ar-condicionado', 'área de lazer', 'quadra',
                         'sauna', 'quintal', 'jardim', 'interfone', 'cerca elétrica', 'segurança 24h'];
  n      int;
BEGIN
  IF p_codigo IS NULL OR btrim(q) = '' THEN RETURN NULL; END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL OR coalesce(i.e_parceiro, false) THEN RETURN NULL; END IF;
  car   := lower(unaccent(coalesce(array_to_string(i.caracteristicas, ', '), '') || ', ' || coalesce(i.extras->>'caracteristicas', '')));
  dorig := coalesce(nay_descricao_segura(i.descricao), '');
  des   := lower(unaccent(dorig));
  v_inc := lower(unaccent(coalesce(i.extras->>'incluso no aluguel', '')));

  -- A ficha basica, escrita uma vez: serve de resposta quando ele pergunta
  -- isso, e de lista depois da afirmacao quando ele pergunta outra coisa.
  f_q := CASE WHEN coalesce(i.quartos, 0) > 0 THEN
           'tem ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ||
           CASE WHEN coalesce(i.suites, 0) > 0 THEN ', sendo ' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END END;
  f_b := CASE WHEN coalesce(i.banheiros, 0) > 0 THEN
           'tem ' || i.banheiros || CASE WHEN i.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END END;
  -- VAGAS: NULL em vagas_cobertas e "nao sei", nao "nenhuma" -- mesma regra do card.
  f_v := CASE
           WHEN coalesce(i.vagas, 0) = 0 AND coalesce(i.vagas_cobertas, 0) > 0
             THEN 'tem ' || i.vagas_cobertas || CASE WHEN i.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
           WHEN coalesce(i.vagas, 0) = 0 THEN NULL
           WHEN i.vagas_cobertas IS NULL THEN 'tem ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga de garagem' ELSE ' vagas de garagem' END
           WHEN i.vagas_cobertas = 0 THEN 'tem ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga descoberta' ELSE ' vagas descobertas' END
           WHEN i.vagas_cobertas >= i.vagas THEN 'tem ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
           ELSE 'tem ' || i.vagas || ' vagas, sendo ' || i.vagas_cobertas || CASE WHEN i.vagas_cobertas = 1 THEN ' coberta' ELSE ' cobertas' END END;
  f_a := CASE WHEN coalesce(i.area_util, 0) > 0 THEN 'tem ' || trim(to_char(i.area_util, 'FM999990')) || ' m²' END;
  f_an := CASE WHEN coalesce(i.andar, '') <> '' THEN
            CASE WHEN i.andar ~ '^\d+$' THEN 'fica no ' || i.andar || 'º andar' ELSE 'fica no andar ' || i.andar END END;

  -- MOBILIA ("e mobiliado?", "vem com moveis?", "tem armario planejado?", "e vazio?").
  -- Duas partes: a afirmacao e o detalhe, que vira a primeira linha da lista.
  IF q ~ '(mobil|\mmovel|moveis|semi.?mob|\mvazio|equipad|planejad|armario|guarda.?roupa|geladeira|fogao|\mcama\M)' THEN
    IF lower(coalesce(i.mobilia, '')) ~ '^semi' THEN
      r := r || 'é semi-mobiliado'::text || 'tem móveis planejados e ar-condicionado'::text;
    ELSIF lower(coalesce(i.mobilia, '')) ~ '^mobiliad' THEN
      r := r || 'é mobiliado'::text || 'tem móveis, cama e tudo'::text;
    ELSIF lower(coalesce(i.mobilia, '')) ~ 'ar.condicionado' THEN
      r := r || 'não é mobiliado'::text || 'tem só o ar-condicionado'::text;
    ELSIF car ~ 'semi.?mobiliad' THEN
      r := r || 'é semi-mobiliado'::text;
    ELSIF car ~ '(sem mobilia|nao mobiliad)' THEN
      r := r || 'não é mobiliado'::text;
    ELSIF car ~ 'mobiliad' THEN
      r := r || 'é mobiliado'::text;
    END IF;
  END IF;

  IF q ~ '(quarto|dormitorio|suite)' AND f_q IS NOT NULL THEN r := r || f_q; END IF;
  IF q ~ '(banheiro|\mwc\M|lavabo|sanitario)' AND f_b IS NOT NULL THEN r := r || f_b; END IF;
  IF q ~ '(\mvaga|garagem|estacionamento|\mcarro)' AND f_v IS NOT NULL THEN r := r || f_v; END IF;
  IF q ~ '(\marea\M|metragem|tamanho|\mm2\M|\mmetros|metro quadrado)' AND f_a IS NOT NULL THEN r := r || f_a; END IF;
  IF q ~ '(\mandar|pavimento)' AND f_an IS NOT NULL THEN r := r || f_an; END IF;

  -- SOL
  IF q ~ '(\msol\M|nascente|poente|posicao do sol|lado do sol)' AND coalesce(i.sol, '') <> '' THEN
    r := r || ('é ' || lower(i.sol));
  END IF;

  -- NOME DO CONDOMINIO
  IF q ~ '(qual|nome).{0,15}(condominio|predio|residencial|edificio)' AND q !~ '(taxa|valor|\mquanto\M|preco|custa)'
     AND coalesce(nai_condominio_ok(i.condominio_nome), '') <> '' THEN
    r := r || ('fica no ' || nai_condominio_ok(i.condominio_nome));
  -- TAXA DE CONDOMINIO
  ELSIF q ~ '(taxa|condominio)' AND q ~ '(taxa|valor|\mquanto\M|preco|custa|inclus|\mpaga)' THEN
    IF v_inc ~ 'condom' THEN
      r := r || 'a taxa de condomínio já está inclusa no aluguel'::text;
    ELSIF coalesce(i.taxa_condominio, 0) > 0 THEN
      r := r || ('a taxa de condomínio é R$ ' || replace(to_char(i.taxa_condominio, 'FM999,999,990'), ',', '.'));
    END IF;
  END IF;

  -- IPTU
  IF q ~ 'iptu' THEN
    IF v_inc ~ 'iptu' THEN
      r := r || 'o IPTU já está incluso no aluguel'::text;
    ELSIF coalesce(i.iptu, 0) > 0 THEN
      r := r || ('o IPTU é R$ ' || replace(to_char(i.iptu, 'FM999,999,990'), ',', '.'));
    END IF;
  END IF;

  -- VALOR (aluguel / venda)
  IF q ~ '(valor|preco|\mquanto\M|aluguel|custa|mensal)' AND q !~ '(condominio|iptu|taxa)' THEN
    IF q ~ '(venda|vender|compra)' AND coalesce(i.valor_venda, 0) > 0 THEN
      r := r || ('o valor de venda é R$ ' || replace(to_char(i.valor_venda, 'FM999,999,990'), ',', '.'));
    ELSIF coalesce(i.valor_aluguel, 0) > 0 THEN
      r := r || ('o aluguel é R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.') ||
                 CASE WHEN v_inc ~ 'condom' THEN ', já com a taxa de condomínio inclusa' ELSE '' END);
    END IF;
  END IF;

  -- DISPONIBILIDADE
  IF q ~ '(disponivel|disponibilidade|ainda (tem|esta|ta)|\mlivre|alugado|\mvago\M|ja alugou)' THEN
    r := r || CASE WHEN nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                   THEN 'está disponível' ELSE 'não está mais disponível' END;
  END IF;

  -- ONDE FICA (nunca o numero do predio, da casa ou do apartamento)
  IF q ~ '(bairro|onde fica|localiza|endereco|\mrua\M|regiao|\mzona\M)' THEN
    v_fr := concat_ws(', ',
      CASE WHEN coalesce(nai_condominio_ok(i.condominio_nome), '') <> '' THEN 'no ' || nai_condominio_ok(i.condominio_nome) END,
      CASE WHEN coalesce(nay_endereco_sem_numero(i.logradouro), '') <> '' THEN 'na ' || nay_endereco_sem_numero(i.logradouro) END,
      CASE WHEN coalesce(i.bairro, '') <> '' THEN 'bairro ' || i.bairro END);
    IF coalesce(v_fr, '') <> '' THEN r := r || ('fica ' || v_fr); END IF;
  END IF;

  -- FINANCIAMENTO (venda)
  IF q ~ 'financ' AND coalesce(i.valor_venda, 0) > 0 THEN
    IF coalesce(i.extras->>'aceita financiamento', '') ~* '^s' THEN r := r || 'aceita financiamento'::text;
    ELSIF coalesce(i.extras->>'aceita financiamento', '') ~* '^n' THEN r := r || 'não aceita financiamento'::text; END IF;
  END IF;

  -- PET: so quando o anuncio fala (a frase dele, sem numero de unidade)
  IF q ~ '(\mpet|animal|animais|cachorro|\mgato|bicho|\mcao\M)' THEN
    v_fr := (regexp_match(dorig, '[^.!?\n]*(?:\mpet|animal|animais|cachorro|gato)[^.!?\n]*', 'i'))[1];
    IF coalesce(btrim(v_fr), '') <> '' THEN r := r || ('sobre pet, o anúncio diz: "' || btrim(v_fr) || '"'); END IF;
  END IF;

  -- LAZER / CARACTERISTICAS: so afirma o que o cadastro ou o anuncio dizem
  FOR n IN 1 .. array_length(busca, 1) LOOP
    IF position(busca[n] IN q) > 0 AND (position(busca[n] IN car) > 0 OR position(busca[n] IN des) > 0)
       AND NOT (('tem ' || exibe[n]) = ANY (r)) THEN
      r := r || ('tem ' || exibe[n]);
    END IF;
  END LOOP;

  IF coalesce(array_length(r, 1), 0) = 0 THEN RETURN NULL; END IF;

  -- A AFIRMACAO (Tel, 13/09): "Sim!" so quando a pergunta e de sim ou nao --
  -- "quantos quartos?" nao se responde com "Sim!". Resposta negativa fica sem
  -- o "Sim", ela mesma ja nega.
  v_out := nai_frase_maiuscula(r[1]);
  -- "Sim!" so quando a resposta e um sim inteiro. Em "e mobiliado?" com imovel
  -- SEMI-mobiliado, "Sim! E semi-mobiliado" engana o corretor: fica so a frase.
  IF q !~ '(qual|quais|quanto|quantos|quantas|onde|como)'
     AND r[1] !~ '^n[ãa]o' AND r[1] !~ '^é semi' THEN
    v_out := 'Sim! ' || v_out;
  END IF;

  -- A LISTA: o resto do que ele perguntou, e depois a ficha do imovel.
  FOR n IN 2 .. coalesce(array_length(r, 1), 1) LOOP
    linhas := linhas || nai_frase_maiuscula(r[n]);
  END LOOP;
  FOREACH v_fr IN ARRAY ARRAY[f_q, f_b, f_v, f_a, f_an] LOOP
    IF v_fr IS NOT NULL AND NOT (v_fr = ANY (r)) THEN linhas := linhas || nai_frase_maiuscula(v_fr); END IF;
  END LOOP;

  IF coalesce(array_length(linhas, 1), 0) = 0 THEN RETURN v_out; END IF;
  RETURN v_out || E'\n\n' || array_to_string(linhas, E'\n');
END;
$$;

-- "tem 3 quartos" -> "Tem 3 quartos." (uma frase por linha, sem emoji)
CREATE OR REPLACE FUNCTION nai_frase_maiuscula(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT upper(left(btrim(coalesce(p, '')), 1)) || substr(btrim(coalesce(p, '')), 2) ||
         CASE WHEN right(btrim(coalesce(p, '')), 1) IN ('.', '!', '?', '"') THEN '' ELSE '.' END;
$$;

-- A ferramenta `o_que_sei_do_imovel` da NAI passa por aqui: primeiro a ficha
-- (resposta pronta, sabe=true), depois o que o Tel ja explicou (a funcao antiga,
-- intacta -- a Nay antiga continua usando ela direto).
CREATE OR REPLACE FUNCTION nai_o_que_sei_do_imovel(p_codigo text, p_pergunta text)
RETURNS TABLE(texto_pronto text, sabe boolean, instrucao_para_voce text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
  v_base text;
BEGIN
  IF length(v_cod) BETWEEN 3 AND 5 THEN
    v_base := nai_resposta_da_base(v_cod::int, p_pergunta);
  END IF;
  IF v_base IS NOT NULL THEN
    RETURN QUERY SELECT v_base, true,
      ('isto esta na ficha do imovel: mande o texto_pronto EXATAMENTE como veio, com as quebras de linha, ' ||
       'sem resumir, sem juntar numa frase so e sem emoji. NAO escale. NAO emende convite de visita: o sistema manda isso sozinho.')::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT x.texto_pronto, x.sabe, x.instrucao_para_voce FROM nay_o_que_sei_do_imovel(p_codigo, p_pergunta) x;
END;
$$;
