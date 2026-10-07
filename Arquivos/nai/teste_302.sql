-- dentro do ensaio (ROLLBACK no fim): um corretor de verdade, sem visita aberta, confirma a visita de um imóvel de
-- verdade com proprietário e telefone no cadastro. Nada disto sai: a caixa é desfeita junto com a transação.
CREATE TEMP TABLE _t302 ON COMMIT DROP AS
SELECT k.id AS contato, k.chave, k.telefone,
       (SELECT i.codigo FROM imoveis i
         WHERE i.disponivel AND NOT i.e_parceiro AND coalesce(i.publicado_no_site, false)
           AND (SELECT d.motivo FROM nai_proprietario_do_imovel(i.codigo) d) IS NULL
         ORDER BY i.codigo DESC LIMIT 1) AS codigo
  FROM nai_contato k JOIN corretores c ON nai_chave(c.telefone) = k.chave
 WHERE c.pode_falar AND c.ativo AND NOT nai_e_da_equipe_contato(k.id)
   AND nai_com_a_rayssa(k.id, 'corretor') IS NULL
   AND NOT EXISTS (SELECT 1 FROM nai_visita v
                    WHERE v.corretor_id = ANY (coalesce(nai_contato_irmaos(k.id), ARRAY[k.id])) AND nai_visita_aberta(v.estado))
 ORDER BY k.id DESC LIMIT 1;

SELECT right(chave, 4) AS corretor_fim, codigo AS imovel,
       nai_com_a_rayssa(contato, 'corretor') AS antes_com_a_rayssa,
       nai_core_atende(contato, 'bom dia') AS antes_o_core_atende
  FROM _t302;

-- o "sim" do corretor, como o worker do nay-core chama (visita para amanhã às 10h de Manaus, sem turno do velho)
CREATE TEMP TABLE _r302 ON COMMIT DROP AS
SELECT nai_core_visita_confirmada(chave, codigo,
         (date_trunc('day', now() AT TIME ZONE 'America/Manaus') + interval '1 day 10 hours') AT TIME ZONE 'America/Manaus',
         NULL) AS r
  FROM _t302;
SELECT r ->> 'ok' AS ok, r ->> 'estado' AS estado, r ->> 'ja_existia' AS ja_existia FROM _r302;

-- 1. a visita existe, confirmada e com a Rayssa
SELECT v.estado, v.aguardando, to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS quando,
       v.confirmada_corretor_em IS NOT NULL AS confirmada, v.aprovada_por
  FROM nai_visita v, _r302 WHERE v.id = (r ->> 'visita_id')::bigint;

-- 2. o que entrou na caixa: proprietário, Rayssa (equipe) e Tel, uma mensagem para cada
SELECT s.papel_destino AS para, s.motivo, s.estado,
       left(regexp_replace(regexp_replace(s.texto, E'[\\n\\r]+', ' / ', 'g'), '\d{8,}', '[telefone]', 'g'), 230) AS texto
  FROM nai_saida s, _r302 WHERE s.visita_id = (r ->> 'visita_id')::bigint ORDER BY s.id;

-- 3. a Nay para de responder o corretor (a porta devolve o motivo) e o núcleo novo não recebe o turno
SELECT nai_com_a_rayssa(contato, 'corretor') AS depois_com_a_rayssa,
       nai_core_atende(contato, 'bom dia') AS depois_o_core_atende
  FROM _t302;

-- 4. o CRM: a marca que põe o corretor na etapa Visitas
SELECT m.visita_rayssa AS crm_etapa_visitas, m.visita_id IS NOT NULL AS com_a_visita
  FROM _t302 t, crm_parceria_com_a_rayssa(ARRAY[t.telefone]) m;

-- 5. confirmar de novo não cria outra visita nem avisa de novo
SELECT nai_core_visita_confirmada(chave, codigo, now() + interval '1 day', NULL) ->> 'ja_existia' AS de_novo_ja_existia,
       (SELECT count(*) FROM nai_visita v WHERE v.corretor_id = contato AND v.codigo = _t302.codigo
          AND nai_visita_aberta(v.estado)) AS visitas_abertas,
       (SELECT count(*) FROM nai_saida s, _r302 WHERE s.visita_id = (r ->> 'visita_id')::bigint) AS mensagens_na_caixa
  FROM _t302;

-- 6. recusa o que não dá para marcar
SELECT nai_core_visita_confirmada('5500000000000', 3078, now() + interval '1 day') ->> 'motivo' AS sem_contato,
       (SELECT nai_core_visita_confirmada(chave, -1, now() + interval '1 day') ->> 'motivo' FROM _t302) AS sem_imovel;
