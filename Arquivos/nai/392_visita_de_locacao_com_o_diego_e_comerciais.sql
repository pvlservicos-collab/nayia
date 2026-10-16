-- 392: a visita de LOCAÇÃO da Nay do WhatsApp chama o Diego (não corretor); galpão/prédio/sala/loja na busca, sem mobília;
--      o acompanhamento de 10 min; e o resto das perguntas sem resposta na fila do PV do Tel
--
-- Pedro, 16/10/2026: "quando for imóvel de locação não vai chamar corretor a Nay dos leads da OLX e sim o Diego direto, ela
-- vai chamar corretor só para venda. Diego, salve no sistema nosso motoboy e corretor interno +55 92 8209-2845 ... se for
-- locação pode falar com o Diego ou com o corretor para organizar agenda, e depois de um ok de um ou de outro aí sim falar
-- com o proprietário"; "quando é galpão ou prédio comercial a gente não pergunta se quer mobiliado ou semi"; "ela deve
-- sempre vir depois de uns 10 minutos fazer o follow up com o cliente"; e, da 391, "liste logo as que ainda não têm
-- resposta" (as de antes de 14/10 tinham ficado de fora) + "pare de me pedir confirmação".
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '20s';

-- o Diego: motoboy e corretor interno (papel próprio: o acompanhante da agenda da Parceria continua o André)
INSERT INTO equipe (telefone, nome, papel) VALUES ('5592982092845', 'Diego Soares', 'corretor_interno')
ON CONFLICT (telefone) DO UPDATE SET nome = EXCLUDED.nome, papel = EXCLUDED.papel, ativo = true;

INSERT INTO privado.olx_config (chave, valor, descricao) VALUES
  ('visita_locacao', 'Diego:5592982092845',
   '392: na visita de LOCAÇÃO a Nay do WhatsApp chama estes primeiro ("Nome:telefone, ..."), depois os de visita_corretores; na venda, só os corretores'),
  ('seguimento_min', '10', '392: minutos de silêncio depois da última mensagem dela para o acompanhamento ("posso estar enviando outras opções semelhantes?")')
ON CONFLICT (chave) DO NOTHING;

ALTER TABLE privado.olx_lead_whatsapp ADD COLUMN IF NOT EXISTS seguimento_em timestamptz;

-- a busca: galpão, prédio, sala, loja, terreno e "comercial"; no comercial não há quarto nem mobília
CREATE OR REPLACE FUNCTION public.olx_cliente_buscar(p_filtros jsonb, p_excluir integer[] DEFAULT '{}'::integer[], p_limite integer DEFAULT 5)
 RETURNS TABLE(codigo integer, bairro text, condominio text, tipo text, quartos integer, preco numeric, perto boolean)
 LANGUAGE sql
 STABLE
AS $function$
  WITH f0 AS (
    SELECT CASE WHEN lower(coalesce(p_filtros->>'finalidade', '')) LIKE 'vend%' THEN 'venda' ELSE 'locacao' END AS fin,
           lower(unaccent(coalesce(p_filtros->>'tipo', ''))) AS tipo,
           CASE WHEN coalesce(p_filtros->>'teto', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (p_filtros->>'teto')::numeric END AS teto,
           CASE WHEN coalesce(p_filtros->>'quartos', '') ~ '^[0-9]+$' THEN (p_filtros->>'quartos')::int END AS quartos,
           coalesce(p_filtros->>'aceita_menos_quartos', '') = 'true' AS menos,
           lower(coalesce(p_filtros->>'mobilia', '')) AS mob,
           lower(coalesce(p_filtros->>'financiamento', '')) ~ '(financ|simula|aprovad)' AS financia
  ), f AS (
    SELECT f0.*, f0.tipo IN ('galpao', 'predio', 'sala', 'loja', 'terreno', 'comercial') AS comercial FROM f0
  ), pedidos AS (     -- os bairros que ela disse, no nome do cadastro ("pq 10" -> parque 10 de novembro)
    -- 388: o nome do cadastro parecido; senão o bairro do conjunto/lugar (nai_bairros_do_lugar: "Vieiralves")
    SELECT DISTINCT nay_normalizar_lugar(x, true) AS n
      FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_filtros->'bairros') = 'array' THEN p_filtros->'bairros' ELSE '[]'::jsonb END) b
      CROSS JOIN LATERAL unnest(coalesce(CASE WHEN nay_bairro_parecido(b) IS NOT NULL THEN ARRAY[nay_bairro_parecido(b)] END,
                                         nullif(nai_bairros_do_lugar('no ' || b), '{}'), ARRAY[b])) x
     WHERE btrim(b) <> ''
  ), perto AS (
    SELECT DISTINCT nay_normalizar_lugar(x, true) AS n
      FROM unnest(nai_bairros_ao_redor(ARRAY(SELECT n FROM pedidos))) x
     WHERE nay_normalizar_lugar(x, true) NOT IN (SELECT n FROM pedidos)
  ), c AS (
    SELECT i.codigo, i.bairro, i.condominio_nome, i.tipo, i.quartos, nay_normalizar_lugar(i.bairro, true) AS bn,
           CASE WHEN f.fin = 'venda' THEN i.valor_venda ELSE i.valor_aluguel END AS p
      FROM core_imovel_busca i CROSS JOIN f
      LEFT JOIN imoveis x ON x.codigo = i.codigo
     WHERE i.ofertavel AND NOT coalesce(i.e_parceiro, false)
       AND CASE WHEN f.fin = 'venda' THEN i.de_venda ELSE i.de_locacao END
       AND CASE WHEN f.tipo IN ('', 'tanto_faz') THEN i.tipo IN ('apartamento', 'casa', 'casa_condominio', 'flat', 'cobertura')
                WHEN f.tipo = 'casa' THEN i.tipo IN ('casa', 'casa_condominio')
                -- 392: galpão e prédio moram em 'outro' na busca; o cadastro diz qual
                WHEN f.tipo = 'galpao' THEN i.tipo = 'outro' AND lower(unaccent(coalesce(x.tipo, ''))) LIKE 'galp%'
                WHEN f.tipo = 'predio' THEN i.tipo = 'outro' AND lower(unaccent(coalesce(x.tipo, ''))) LIKE 'predio%'
                WHEN f.tipo = 'comercial' THEN i.tipo IN ('sala', 'loja')
                                          OR (i.tipo = 'outro' AND lower(unaccent(coalesce(x.tipo, ''))) ~ '^(galp|predio)')
                ELSE i.tipo = f.tipo END
       AND (f.comercial OR f.quartos IS NULL OR coalesce(i.quartos, 0) >= f.quartos - CASE WHEN f.menos THEN 1 ELSE 0 END)
       -- 388: "modulados e ar" (semi) também aceita o mobiliado; mobiliado é só mobiliado. 392: no comercial não conta
       AND (f.comercial OR f.mob NOT IN ('mobiliado', 'semi') OR i.mobilia = f.mob OR (f.mob = 'semi' AND i.mobilia = 'mobiliado'))
       AND NOT (i.codigo = ANY (coalesce(p_excluir, '{}')))
       -- quem vai financiar não recebe imóvel que não aceita financiamento (a regra dos pedidos dos grupos, 371)
       AND NOT (f.fin = 'venda' AND f.financia AND lower(coalesce(x.extras->>'aceita financiamento', '')) LIKE 'n%')
  )
  SELECT c.codigo, c.bairro, c.condominio_nome, c.tipo, c.quartos, c.p, (c.bn IN (SELECT n FROM perto))
    FROM c CROSS JOIN f
   WHERE c.p > 0
     AND (f.teto IS NULL OR c.p BETWEEN f.teto * 0.75 AND f.teto * 1.10)
     AND (NOT EXISTS (SELECT 1 FROM pedidos) OR c.bn IN (SELECT n FROM pedidos) OR c.bn IN (SELECT n FROM perto))
   ORDER BY (c.bn IN (SELECT n FROM perto)), abs(c.p - coalesce(f.teto, c.p)), c.codigo
   LIMIT least(greatest(coalesce(p_limite, 5), 1), 10)
$function$;

-- a fila (391): a pendência antiga respondida ou descartada pela fila fecha lá também
DO $do$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.pergunta_fila_responder(bigint,bigint,text,text)'::regprocedure);
  IF position('origem = ''pendencias''' IN d) = 0 THEN
    d := replace(d, '    v_msg := ''Tirei da fila a pergunta ''',
                 '    IF f.origem = ''pendencias'' THEN' || E'\n'
                 || '      UPDATE pendencias SET status = ''descartada'', respondida_em = now() WHERE id = f.origem_id;' || E'\n'
                 || '    END IF;' || E'\n'
                 || '    v_msg := ''Tirei da fila a pergunta ''');
    d := replace(d, '    -- a memória: com o código',
                 '    IF f.origem = ''pendencias'' THEN' || E'\n'
                 || '      UPDATE pendencias SET status = ''respondida'', resposta = s, respondida_em = now() WHERE id = f.origem_id;' || E'\n'
                 || '    END IF;' || E'\n'
                 || '    -- a memória: com o código');
    IF (length(d) - length(replace(d, 'origem = ''pendencias''', ''))) / length('origem = ''pendencias''') <> 2 THEN
      RAISE EXCEPTION 'pergunta_fila_responder: as âncoras não bateram';
    END IF;
    EXECUTE d;
  END IF;
END
$do$;

-- as que ainda não têm resposta e tinham ficado de fora, no FIM da fila (as de agora são respondidas primeiro):
-- as da Nay nova de 05/10 a 13/10 e as pendências do caminho antigo (o lembrete de 6 em 6 h para de listá-las)
SELECT pergunta_fila_entrar('parceria', p.chave, NULL, p.codigo, NULL, p.pergunta, 'core_pendencia', p.id,
                            array_to_string(array_remove(p.faltou, 'assunto nao reconhecido'), ', '))
  FROM core_pendencia_aberta p
 WHERE p.criado_em < '2026-10-14 00:00-04'
 ORDER BY p.id;

WITH entrou AS (
  SELECT p.id, pergunta_fila_entrar('parceria', p.avisar, NULL,
                                    CASE WHEN btrim(coalesce(p.codigo, '')) ~ '^\d{1,6}$' THEN btrim(p.codigo)::int END,
                                    NULL, p.o_que_falta, 'pendencias', p.id) AS fila
    FROM pendencias p
   WHERE p.status = 'aberta'
   ORDER BY p.id)
UPDATE pendencias SET status = 'na_fila' WHERE id IN (SELECT id FROM entrou WHERE fila IS NOT NULL);

COMMIT;
