-- 607 (Pedro, 04/11/2026: "faz o cadastro desse imóvel, analisa certinho e me diz informações que faltam 92 9 9112-5619").
-- A Sra. Ruth Ximenes de Sabóia (proprietária 2240, a mesma do 286, os dois com o mesmo telefone) mandou na Parceria,
-- às 11:29-11:32 de 04/11, a descrição, 27 fotos, 2 vídeos, os projetos de interiores e as plantas baixas
-- (arquiteta Carla Rocha, março/2025): casa no Cond. Alphaville Manaus II, Lote 11, Qd. E2, Rua D1, à venda por
-- R$ 4.200.000 ("podemos avaliar propostas"). Em 26/10 ela já tinha oferecido: comissão de R$ 200.000 se vender pelo
-- valor anunciado; abaixo dele, 4%.
-- Nasce RASCUNHO (fora do site e da Nay) e SEM FOTOS: ela escreveu que as fotos são de outro corretor e "não servem para
-- divulgação em nenhum portal ou rede social"; precisamos fazer as nossas.
BEGIN;

DO $$
DECLARE
  v int;
BEGIN
  INSERT INTO imoveis (codigo, origem, status, disponivel, publicado_no_site, criado_em, captado_em, e_parceiro,
                       proprietario_id, tipo, condo_id, condominio_nome, bairro, cidade, estado, logradouro, cep,
                       area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas, valor_venda, mobilia,
                       descricao, caracteristicas, extras)
  VALUES (nextval('imoveis_crm_codigo_seq'), 'crm', 'Rascunho', false, false, now(), to_char(now(), 'DD/MM/YYYY'), false,
          2240, 'Casa de condomínio', 456, 'Alphaville 2', 'Ponta Negra', 'Manaus', 'AM', 'Avenida José Augusto Loureiro',
          '69037-225',
          466.63, 500.57, 5, 5, 7, 4, 2, 4200000, 'sem nada',
          'Casa de alto padrão no Alphaville 2, em 2 pavimentos, com 466,63 m² de área construída em terreno de 500,57 m². '
          || 'Térreo: hall de entrada com pé-direito duplo, sala de estar integrada, sala de jantar, lavabo, cozinha com ilha, '
          || 'varanda gourmet integrada à área social com churrasqueira e bancada, uma suíte com closet, despensa, lavanderia, '
          || 'depósito e banheiro externo. Superior: suíte master com closet, varanda, duas cubas e banheira de hidromassagem, '
          || 'mais três suítes com closet (uma com varanda) e escritório. Área externa com piscina com prainha e cascata, '
          || 'ofurô, deck em madeira de lei e solarium, e jardim paisagístico. Garagem coberta para 2 carros e descoberta para '
          || 'mais 2. Casa de máquinas da piscina e casa de gás. Materiais nobres (pedras naturais e madeira maciça), esquadrias '
          || 'premium, projeto de iluminação e louças e metais Deca.',
          ARRAY['Piscina', 'Closet', 'Escritório', 'Hidromassagem', 'Banheira', 'Churrasqueira', 'Espaço gourmet',
                'Área de serviço', 'Varanda', 'Jardim', 'Condomínio fechado', 'lavabo', 'depósito', 'despensa',
                'banheiro de serviço', 'duplex'],
          jsonb_build_object('tamanho do terreno', '500.57', 'area construida', '466.63', 'fino acabamento', 'Sim',
                             'salas', '2', 'indicado por', 'Proprietária (Parceria, 04/11)'))
  RETURNING codigo INTO v;

  -- o dono mora em DOIS lugares; a Nay lê o do imovel_privado
  INSERT INTO imovel_privado (codigo, proprietario_id, lote, rua)
  VALUES (v, 2240, '11, quadra E2', 'Rua D1')
  ON CONFLICT (codigo) DO UPDATE SET proprietario_id = EXCLUDED.proprietario_id, lote = EXCLUDED.lote, rua = EXCLUDED.rua;

  PERFORM privado.uso_interno_somar(v,
    'Proprietária: Ruth Ximenes de Sabóia (92 99112-5619), pela Parceria, 04/11. Comissão que ELA ofereceu em 26/10: '
    || 'R$ 200.000 se vender por R$ 4.200.000; abaixo desse valor, 4%. "Vamos tentar fechar por R$ 4.200.000, mas podemos '
    || 'avaliar propostas." FOTOS: as 27 que ela mandou são de outro corretor e ela proibiu usar em portal ou rede social; '
    || 'fazer fotos nossas antes de publicar (as dela, os 2 vídeos, as plantas e os projetos de interiores estão na conversa '
    || 'dela no CRM). Endereço: Cond. Alphaville Manaus II, Lote 11, Qd. E2, Rua D1 (plantas da arq. Carla Rocha, mar/2025).');

  RAISE NOTICE 'casa da Ruth = #% (aplicada em 04/11: #9137)', v;
END $$;

SELECT i.codigo, i.status, i.disponivel, i.publicado_no_site, i.tipo, i.condominio_nome, i.area_util, i.area_total,
       i.quartos, i.suites, i.banheiros, i.vagas, i.valor_venda, i.taxa_condominio, i.proprietario_id,
       p.proprietario_id AS dono_privado, p.lote, p.rua
  FROM imoveis i JOIN imovel_privado p USING (codigo)
 WHERE i.origem = 'crm' AND i.condo_id = 456 AND i.criado_em > now() - interval '1 hour';
COMMIT;
