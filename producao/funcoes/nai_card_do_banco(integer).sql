CREATE OR REPLACE FUNCTION public.nai_card_do_banco(p_codigo integer)
 RETURNS TABLE(texto_pronto text, qtd_fotos integer)
 LANGUAGE sql
 STABLE
AS $function$
  WITH b AS (
    SELECT i.*,
           CASE WHEN coalesce(nai_condominio_ok(i.condominio_nome), '') <> ''
                THEN nai_condominio_ok(i.condominio_nome)
                WHEN coalesce(i.bairro, '') = '' THEN coalesce(i.tipo, 'Imóvel ' || i.codigo)
                WHEN lower(i.bairro) ~ '^(conjunto|conj\.|cj)' THEN coalesce(i.tipo, 'Imóvel') || ' ' || i.bairro
                ELSE coalesce(i.tipo, 'Imóvel') || ' bairro ' || i.bairro END AS titulo
      FROM imoveis i WHERE i.codigo = p_codigo)
  SELECT
    CASE WHEN coalesce(b.e_parceiro, false) THEN
      '📍 ' || b.titulo || E'
• esse imovel e de parceria, nao da imob easy.'
    ELSE
      '📍 ' || b.titulo
      || CASE WHEN coalesce(b.bairro, '') <> '' AND position(lower(b.bairro) IN lower(b.titulo)) = 0
              THEN E'
• Bairro: ' || b.bairro ELSE '' END
      || CASE WHEN coalesce(b.area_util, 0) > 0 THEN E'
• ' || trim(to_char(b.area_util, 'FM999990')) || 'm2' ELSE '' END
      || CASE WHEN coalesce(b.quartos, 0) > 0 THEN E'
• ' || b.quartos || CASE WHEN b.quartos = 1 THEN ' quarto' ELSE ' quartos' END
              || CASE WHEN coalesce(b.suites, 0) > 0 THEN ' sendo ' || b.suites || CASE WHEN b.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END ELSE '' END
      || CASE WHEN coalesce(b.banheiros, 0) > 0 THEN E'
• ' || b.banheiros || CASE WHEN b.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END ELSE '' END
      -- vagas: NULL em vagas_cobertas e "nao sei", nao "nenhuma" (mesma regra do publicador).
      || CASE WHEN coalesce(b.vagas, 0) = 0 AND coalesce(b.vagas_cobertas, 0) > 0
                THEN E'
• ' || b.vagas_cobertas || CASE WHEN b.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
              WHEN coalesce(b.vagas, 0) = 0 THEN ''
              WHEN b.vagas_cobertas IS NULL THEN E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga' ELSE ' vagas' END
              WHEN b.vagas_cobertas = 0 THEN E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga descoberta' ELSE ' vagas descobertas' END
              WHEN b.vagas_cobertas >= b.vagas THEN E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
              ELSE E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga' ELSE ' vagas' END
                   || ' sendo ' || b.vagas_cobertas || CASE WHEN b.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END END
      || CASE WHEN lower(coalesce(b.sol, '')) ~ '^nascente' THEN E'
• nascente'
              WHEN lower(coalesce(b.sol, '')) ~ '^poente' THEN E'
• poente' ELSE '' END
      || CASE WHEN lower(coalesce(b.mobilia, '')) ~ '^semi' THEN E'
• semi-mobiliado'
              WHEN lower(coalesce(b.mobilia, '')) ~ '^mobiliad' THEN E'
• mobiliado'
              WHEN lower(coalesce(b.mobilia, '')) ~ 'ar.condicionado' THEN E'
• climatizado' ELSE '' END
      -- A TAXA DE CONDOMINIO, e so quando e recente (Tel, 03/10). A decisao
      -- ("mostra?") e o formato moram em `nay_linha_da_taxa` -- UMA copia, lida
      -- tambem pelo card do publicador (`montar_mensagem.py`). Taxa sem
      -- carimbo nao sai: `taxa_do_card.sql` explica por que falha fechada.
      || coalesce(E'\n' || nay_linha_da_taxa(b.taxa_condominio, b.taxa_condominio_em), '')
      -- O BULLET EM "Venda:" NAO ENTROU, e nao foi esquecimento (03/10). Ele
      -- escreveu o card do 9013 com "• Venda: R$ 690.000", mas a tela de Grupos
      -- do admin (`grupos-agenda.js`) ancora TRES regex em `^Venda:` e
      -- `^Loca..o:` cruas para tirar o valor que um grupo nao aceita. Com o
      -- bullet elas param de casar e a tela passaria a mostrar ao Tel um post
      -- diferente do que o grupo recebe. Para por o bullet: afrouxar as tres
      -- para `^(?:\u2022\s*)?` ANTES, e so depois mexer aqui.
      || CASE WHEN coalesce(b.valor_venda, 0) > 0
              THEN E'
Venda: R$ ' || replace(to_char(b.valor_venda, 'FM999,999,990'), ',', '.') ELSE '' END
      || CASE WHEN coalesce(b.valor_aluguel, 0) > 0
              THEN E'
Locação: R$ ' || replace(to_char(b.valor_aluguel, 'FM999,999,990'), ',', '.')
                   || CASE WHEN coalesce(b.extras->>'incluso no aluguel', '') ~* 'condom' THEN ' (incluso a tx)' ELSE '' END ELSE '' END
      || E'
Código: ' || b.codigo
    END,
    CASE WHEN coalesce(b.e_parceiro, false) THEN 0 ELSE (SELECT count(*)::int FROM imovel_fotos f WHERE f.codigo = b.codigo) END
  FROM b;
$function$;
