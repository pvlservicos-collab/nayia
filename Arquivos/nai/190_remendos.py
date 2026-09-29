#!/usr/bin/env python3
"""190 -- remenda as funções VIVAS (pg_proc) e gera 190p_remendos.sql.

Roda no servidor da Nay. Nunca reaplicar arquivo antigo destas funções: o
banco está à frente do repositório (ver memória banco-a-frente-do-repositorio).

    python3 190_remendos.py /tmp/cn_190.sql > /tmp/190p.sql
"""
import subprocess, sys


def viva(nome):
    q = f"SELECT pg_get_functiondef('{nome}'::regproc)"
    return subprocess.run(['docker', 'exec', 'nay-postgres', 'psql', '-U', 'nay', '-d', 'naydb', '-At', '-c', q],
                          check=True, capture_output=True, text=True).stdout.rstrip('\n')


def troca(txt, velho, novo, nome):
    n = txt.count(velho)
    if n != 1:
        sys.exit(f'{nome}: trecho aparece {n} vezes (esperado 1): {velho[:90]!r}')
    return txt.replace(velho, novo)


saida = ['-- 190p -- gerado por 190_remendos.py a partir do pg_proc vivo (29/09/2026).',
         '-- Ver o cabeçalho de 190_venda_locacao_e_filtro.sql.', 'BEGIN;', "SET LOCAL lock_timeout = '5s';", '']

# ------------------------------------------------------------ corretor de nomes
cn = open(sys.argv[1], encoding='utf-8').read().replace('NOME_DA_FUNCAO', 'nai_corrigir_nomes')
cn = troca(cn, 'v_troca := v_certo IS NOT NULL AND v_forca >= v_piso;',
           "-- (o 0,0001 e do arredondamento: 1 - 2/10 em double fica abaixo de 0,80 em real)\n"
           "      v_troca := v_certo IS NOT NULL AND v_forca >= v_piso - 0.0001;", 'corrigir_nomes')
saida.append(cn.rstrip().rstrip(';') + ';\n')

# ------------------------------------------------------ imóvel da conversa
f = viva('nai_imovel_da_conversa')
f = troca(f, '  n       int;\nBEGIN', '  n       int;\n  v_neg   text;   -- 190\n  v_dele  int[];  -- 190\nBEGIN', 'imovel_da_conversa')
f = troca(f, "  IF k.id IS NULL THEN RETURN NULL; END IF;\n",
          "  IF k.id IS NULL THEN RETURN NULL; END IF;\n"
          "  -- 190: VENDA NAO E LOCACAO. O imovel da conversa sai so da finalidade da\n"
          "  -- conversa -- salvo o codigo que ele mesmo digitou ou colou. Era por aqui\n"
          "  -- que o 5748 (venda) virou o imovel de quem pedia aluguel no Adrianopolis.\n"
          "  v_neg  := nai_negocio_da_conversa(p_contato, p_texto);\n"
          "  v_dele := nai_codigos_que_ele_digitou(p_contato);\n", 'imovel_da_conversa')
f = troca(f, "      IF coalesce(array_length(v_pelo_nome, 1), 0) = 1 THEN",
          "      v_pelo_nome := ARRAY(SELECT c FROM unnest(v_pelo_nome) c WHERE nai_finalidade_serve(c, v_neg));  -- 190\n"
          "      IF coalesce(array_length(v_pelo_nome, 1), 0) = 1 THEN", 'imovel_da_conversa')
f = troca(f, "  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN NULL; END IF;",
          "  v_cods := ARRAY(SELECT c FROM unnest(v_cods) c WHERE nai_finalidade_serve(c, v_neg) OR c = ANY (v_dele));  -- 190\n"
          "  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN NULL; END IF;", 'imovel_da_conversa')
f = troca(f, "   WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL AND t.criado_em > v_seis\n   ORDER BY t.id DESC LIMIT 1;",
          "   WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL AND t.criado_em > v_seis\n"
          "     AND (nai_finalidade_serve(t.codigo, v_neg) OR t.codigo = ANY (v_dele))  -- 190\n"
          "   ORDER BY t.id DESC LIMIT 1;", 'imovel_da_conversa')
f = troca(f, "  ) y WHERE c IS NOT NULL;\n  IF n = 1 THEN RETURN v_cod; END IF;",
          "  ) y WHERE c IS NOT NULL AND (nai_finalidade_serve(c, v_neg) OR c = ANY (v_dele));  -- 190\n"
          "  IF n = 1 THEN RETURN v_cod; END IF;", 'imovel_da_conversa')
saida.append(f + ';\n')

# ------------------------------------------------------------- conferência
f = viva('nai_conferir_resposta')
f = troca(f, "  IF v_corretor AND v_alvo IS NOT NULL AND coalesce(p_escreveu, '') ~ '\\?'\n     AND v_texto !~* 'c[óo]digo:'\n",
          "  -- 190: a resposta da BUSCA nao vira a ficha de um imovel. Em 29/09 a lista\n"
          "  -- de locacao virou \"Sim! Tem 4 quartos...\" do 5748, de venda.\n"
          "  IF v_corretor AND v_alvo IS NOT NULL AND coalesce(p_escreveu, '') ~ '\\?'\n     AND v_texto !~* 'c[óo]digo:'\n"
          "     AND NOT ('buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}')))\n", 'conferir')
f = troca(f, "  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN\n    v_cods := array_remove(",
          "  -- 190: turno da BUSCA sem card na resposta (pergunta do filtro, lista) nao\n"
          "  -- manda foto do \"imovel da conversa\": as fotos saem quando ele escolher.\n"
          "  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0\n"
          "     AND NOT ('buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}'))) THEN\n    v_cods := array_remove(", 'conferir')
saida.append(f + ';\n')

# ------------------------------------------------ a parede da caixa de saída
f = viva('nai_saida_validar')
f = troca(f, "  v_ind int;\nBEGIN", "  v_ind int;\n  v_fin int;   -- 190\n  v_neg text;  -- 190\nBEGIN", 'saida_validar')
parede = """  -- VENDA NAO SAI EM CONVERSA DE LOCACAO, NEM O CONTRARIO (190, 29/09/2026).
  -- Pedro: "se o cara ta pedindo locacao ela deve continuar enviando locacao, a
  -- nao ser se ele peca claramente venda... ela nunca deve confundir as duas
  -- listas de imoveis sem um pedido claro do corretor". Naquele dia sairam 24
  -- fotos do 5748 (Jardim Adrianopolis, venda, R$ 2 mi) para quem tinha pedido
  -- aluguel de 7 mil na Ponta Negra de manha.
  --
  -- A conversa diz o negocio (`nai_negocio_da_conversa`: a palavra dele, o
  -- valor, e o que ele ja recebeu); o imovel diz a finalidade
  -- (`nai_finalidade_do_imovel`). Nao casou: card e foto ficam 'bloqueado'. O
  -- pedido claro passa: o codigo que ELE digitou ou colou nos ultimos 3 dias.
  -- So resposta a corretor -- o Tel, a entrega e o seguimento ficam de fora.
  IF NEW.papel_destino = 'turno' AND t.papel = 'corretor' THEN
    v_fin := NEW.codigo;
    IF v_fin IS NULL AND NEW.tipo = 'texto'
       AND position('📍' IN coalesce(NEW.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(NEW.texto, 'C[óo]digo:\\s*\\d{3,5}', 'gi')) = 1 THEN
      v_fin := (regexp_match(NEW.texto, 'C[óo]digo:\\s*(\\d{3,5})', 'i'))[1]::int;
    END IF;
    IF v_fin IS NOT NULL AND NOT (v_fin = ANY (nai_codigos_que_ele_digitou(NEW.contato_id))) THEN
      v_neg := nai_negocio_da_conversa(NEW.contato_id, t.texto);
      IF NOT nai_finalidade_serve(v_fin, v_neg) THEN
        NEW.estado   := 'bloqueado';
        NEW.bloqueio := 'finalidade: conversa de ' || v_neg || ', o ' || v_fin || ' e so de '
                        || coalesce(nai_finalidade_do_imovel(v_fin), '?');
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  -- IMOVEL INDISPONIVEL NAO VAI (Tel, 28/09/2026)"""
f = troca(f, "  -- IMOVEL INDISPONIVEL NAO VAI (Tel, 28/09/2026)", parede, 'saida_validar')
saida.append(f + ';\n')

# ---------------------------------------------------------------- a busca
f = viva('nai_buscar_por_perfil')
f = troca(f, "  v_falta      text[];     -- 146: os filtros que ainda da para oferecer\n",
          "  v_falta      text[];     -- 146: os filtros que ainda da para oferecer\n"
          "  v_falta_valor  boolean;  -- 190\n  v_falta_regiao boolean;  -- 190\n  v_abertura     boolean;  -- 190\n", 'busca')
ini = f.index("  IF NOT v_tem_filtro THEN\n    IF v_sem_valor THEN")
fim = f.index("  -- sem bairro, a lista e da cidade toda")
velho = f[ini:fim]
assert velho.count('RETURN;') == 2, velho
novo = """  -- 190: O FILTRO VEM ANTES DE QUALQUER IMOVEL (Pedro, 29/09: "ela precisa
  -- fazer o filtro... sempre que tiver uma nova solicitacao de imoveis...
  -- primeiro fazer o filtro antes de enviar qualquer imovel"). O Sulivam pediu
  -- "casa, na media de 5mil" e a busca listou a cidade inteira sem perguntar a
  -- regiao, porque a 146 listava com QUALQUER filtro na mao. Agora a ordem e:
  -- locacao/venda (144) -> casa/apartamento (152) -> VALOR -> REGIAO, uma
  -- pergunta por mensagem. Quem veio do grupo comeca pela regiao (o fluxo do
  -- site: bairro -> faixa). A 146 continua valendo no que ela tinha de certo:
  -- "o cliente nao disse o valor" e "tanto faz o bairro" pulam a pergunta, e
  -- cada pergunta sai UMA vez por dia (`nai_filtro_ja_perguntado`) -- na
  -- segunda a busca lista com o que tiver.
  -- (Substitui o "sem filtro nenhum, pergunta um de cada vez" da 146.)
  v_falta_valor  := v_teto IS NULL AND NOT v_sem_valor AND NOT v_mostra_logo
                    AND NOT nai_filtro_ja_perguntado(k.id, 'valor');
  v_falta_regiao := nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre
                    AND NOT nai_filtro_ja_perguntado(k.id, 'regiao');
  v_abertura     := NOT nai_filtro_ja_perguntado(k.id, 'abertura');
  IF v_falta_valor AND (v_direta OR NOT v_falta_regiao) THEN
    RETURN QUERY SELECT
      (CASE WHEN v_abertura
            THEN 'Eu vou fazer um filtro com você para poder te enviar as opções que mais podem atender a sua demanda. '
            ELSE '' END || 'Até que valor o seu cliente quer?')::text,
      ('filtro: diga SO essa pergunta. Se ele disser que o cliente nao disse o valor, chame buscar_por_perfil com '
       || 'teto "sem valor". Quando ele responder, chame buscar_por_perfil de novo com tudo o que ele ja disse '
       || '(bairro, teto, mobilia, quartos).')::text;
    RETURN;
  END IF;
  IF v_falta_regiao THEN
    RETURN QUERY SELECT
      (CASE WHEN v_sem_valor THEN 'Sem problema! Qual região ou bairro atende o seu cliente?'
            WHEN NOT v_direta THEN 'Eu também tenho outras opções de ' || v_diz || ', você está procurando imóveis em qual bairro?'
            ELSE 'Qual região ou bairro atende o seu cliente?' END)::text,
      ('filtro: diga SO essa pergunta. Se ele disser que tanto faz o bairro, chame buscar_por_perfil com bairro '
       || 'vazio: a lista sai da cidade toda. Quando ele responder, chame buscar_por_perfil de novo com tudo o que '
       || 'ele ja disse (bairro, teto, mobilia, quartos).')::text;
    RETURN;
  END IF;

"""
f = f[:ini] + novo + f[fim:]
saida.append(f + ';\n')

saida.append('COMMIT;\n')
print('\n'.join(saida))
