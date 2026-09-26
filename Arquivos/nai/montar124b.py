# -*- coding: utf-8 -*-
"""Monta a 124b da funcao VIVA. Uso: python montar124b.py"""
import io

CAB = u"""-- =====================================================================
-- NAI -- 124b: a absorcao roda em TODO turno do cadastro (26/09/2026)
--
-- A 124 ensinou o banco a ler a ficha do texto. Falta o que a faz valer:
-- alguem tem que CHAMAR a leitura a cada mensagem. Se ela so rodar quando
-- o modelo lembrar, volta tudo ao que era -- e o que era sao cinco
-- "Me conta o que e: apartamento, casa ou outra coisa?" seguidos.
--
-- O lugar certo e `nai_mente_registrar`: ele ja procura a ficha aberta em
-- toda mensagem (e a "cola do cadastro" da 121). Achou ficha, absorve o
-- que o corretor acabou de escrever. Uma linha, no caminho que ja existe.
--
-- E o modelo sai em portugues de gente: R$ 3.650,00 e "Locacao" com til.
-- =====================================================================

\\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.nai_cadastro_modelo(p_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- O to_char do Postgres usa o separador da LOCALE, que aqui sai
  -- 3,650.00 -- jeito americano. O translate troca no fim: ponto vira
  -- virgula e virgula vira ponto.
  SELECT '📍 ' || coalesce(n.condominio, n.bairro, 'Imóvel')
    || E'\\n* Bairro: '                  || coalesce(n.bairro, '?')
    || E'\\n* Tamanho: '                 || coalesce(n.area::text || 'm2', '?')
    || E'\\n* Cômodos: '                 || coalesce(n.quartos::text || ' quartos', '?')
         || coalesce(' sendo ' || n.suites::text || ' suíte', '')
    || E'\\n* Banheiros: '               || coalesce(n.banheiros::text || ' banheiros', '?')
    || E'\\n* Vagas de estacionamento: ' || coalesce(n.vagas::text || ' vaga', '?')
    || E'\\n* Mobilia: '                 || coalesce(n.mobilia, '?')
    || E'\\nPreço de '                   || CASE lower(coalesce(n.finalidade, ''))
                                              WHEN 'locacao' THEN 'Locação'
                                              WHEN 'venda'   THEN 'Venda'
                                              ELSE 'Venda ou aluguel' END
         || ': ' || coalesce('R$ ' || translate(to_char(n.valor, 'FM999G999G999D00'),
                                                ',.', '.,'), '?')
  FROM nai_imovel_novo n WHERE n.id = p_id;
$function$;

"""

RODAPE = u"""
COMMIT;

\\echo '=== o modelo, agora em portugues ==='
SELECT nai_cadastro_modelo(13);

\\echo '=== a absorcao esta no caminho de todo turno? ==='
SELECT pg_get_functiondef('nai_mente_registrar'::regproc) ~ 'nai_cadastro_absorver' AS ligada;

-- =====================================================================
-- COMO DESFAZER: reaplicar a 121 (nai_mente_registrar sem a absorcao).
-- =====================================================================
"""

ANCORA = """    IF nai_cfg('cola_solta_no_catalogo','sim') = 'sim'
       AND nai_pergunta_de_catalogo(p->>'texto') THEN"""

NOVO = """    -- O CORRETOR JA RESPONDEU: guarda antes de perguntar de novo (124b).
    -- Sem isto a ficha so era preenchida se o modelo lembrasse de chamar a
    -- ferramenta -- e foi assim que a Nay perguntou cinco vezes a mesma
    -- coisa enquanto ele respondia tudo.
    PERFORM nai_cadastro_absorver(v_ficha, p->>'texto');

    IF nai_cfg('cola_solta_no_catalogo','sim') = 'sim'
       AND nai_pergunta_de_catalogo(p->>'texto') THEN"""


def main():
    f = io.open('mente_viva.txt', encoding='utf-8').read().strip()
    assert f.count(ANCORA) == 1, 'ancora: %d' % f.count(ANCORA)
    f = f.replace(ANCORA, NOVO)
    io.open('124b_absorver_em_todo_turno.sql', 'w', encoding='utf-8', newline='\n').write(
        CAB + f + ";\n" + RODAPE)
    print('escrito')


if __name__ == '__main__':
    main()
