# CONTEXTO: PROJETO MÉTRICAS DA IMOB EASY
Data da conversa: 20/10/2026

## 1. Quem sou e o negócio (FATO, informado por mim)
- Tel, dono da Imob Easy (T A Sobreira Imobiliária, CRECI PJ 482, Lucro Presumido), Manaus/AM.
- Estou em São Paulo. Me mudo para Manaus em 27/10/2026 e passo a atender lead também como corretor.
- Modelo: capto imóveis de terceiros sem exclusividade, direto com o proprietário, e repasso para cerca de 200 corretores parceiros por grupo de WhatsApp. Desde out/2026 também atendo lead direto (OLX, Instagram, tráfego pago) com SDRs e corretores da casa.
- Ticket médio de venda: R$350 mil a R$600 mil. Também faço locação e administração de locação (10% a 12% do aluguel).
- Equipe: Pedro (automações e CRM), Rayssa (atendimento), motoboy (visitas, vistoria, fotos), 3 corretores da casa, 3 vagas de SDR sem fixo (venda, locação, captação). Nay Mendes: IA que atende corretores parceiros no WhatsApp, ainda com erros.
- Comissões: venda 5% a 6%. Parceiro 50/50. Corretor da casa: 40% do que a Imob Easy recebe. SDR: 10% do que a Imob Easy recebe. Rayssa: 10% só em locação.
- Histórico: nos primeiros ~45 dias fechei 2 vendas: uma de R$720 mil em parceria (55% Imob Easy / 45% corretor) e uma de R$600 mil atendida por mim, comissão de 5%.

## 2. Meta
- Lucrar R$200 mil em contratos assinados até 27/12/2026 (conta assinatura, não precisa ter recebido).
- Não inclui cerca de R$54 mil de recebíveis de negócios já fechados.
- Prazo: de 20/10 a 27/12 = 68 dias = 9,7 semanas.

## 3. Lucro por contrato (CÁLCULO feito na conversa)
Base: imóvel de R$475 mil, comissão de 5,5% = R$26.125 (100% da comissão). Valores ANTES de imposto (alíquota ainda não informada).

| Quem fecha | Sobra para a Imob Easy | Contratos para R$200 mil |
|---|---|---|
| Tel sozinho, imóvel próprio | R$26.125 (100%) | 8 |
| Tel + SDR | R$23.512 (90%) | 9 |
| Corretor da casa, imóvel próprio, sem SDR | R$15.675 (60%) | 13 |
| Parceiro 50/50 | R$13.062 (50%) | 16 |
| Corretor da casa + SDR, imóvel próprio | R$13.062 (50%) | 16 |
| Parceiro + SDR | R$11.756 (45%) | 18 |
| Lead próprio + imóvel de parceiro + corretor da casa + SDR | R$6.531 (25%) | 31 |

Conclusões:
- Ritmo histórico: cerca de 0,3 contrato por semana (2 em ~45 dias).
- Ritmo necessário no cenário do meio (16 contratos): 1,65 por semana. Cerca de 5 vezes o ritmo histórico.
- Maior alavanca: o próprio Tel fechando a partir de 27/10 (90% a 100% de margem, o dobro de uma venda de parceiro).
- Pior margem: lead próprio vendido em imóvel de parceiro (25%). SDR precisa priorizar o catálogo próprio.

## 4. Os 10 indicadores definidos

Mudanças em relação à lista original:
- "Custo por lead" virou "custo por visita" (lead barato que não visita engana). Gasto e número de leads continuam anotados.
- "Lucro por contrato" deixou de ser indicador e virou campo de cada contrato.
- Entrou "pipeline previsto até 27/12".
- Funil (indicadores 4, 5 e 6) medido em duas linhas separadas: lead próprio e corretor parceiro.

| # | Indicador | Fonte | Quem preenche | Frequência |
|---|---|---|---|---|
| 1 | Leads novos por origem (OLX, Instagram, tráfego, portal, indicação) | CRM, campo "origem" obrigatório | SDR marca, Pedro extrai | Semanal |
| 2 | Custo por visita realizada (gasto de tráfego ÷ visitas de lead de tráfego) | Gerenciador de Anúncios da Meta + CRM | Tel | Semanal |
| 3 | Tempo de primeira resposta (mediana, minutos, horário comercial) | Horário de chegada x primeira resposta no CRM/Z-API | Pedro (automático) | Semanal |
| 4 | Lead para visita realizada (%) | CRM | SDR | Semanal |
| 5 | Visita para proposta (%) | CRM + relatório do motoboy | Corretor que visitou | Semanal |
| 6 | Proposta para contrato assinado (%) | Registro de contratos | Tel | Semanal |
| 7 | Pipeline: lucro previsto das propostas abertas com assinatura prevista até 27/12 (R$ e % da meta) | Planilha de negócios | Tel | Semanal |
| 8 | Captações novas de proprietário | CRM | Tel / SDR de captação | Semanal |
| 9 | Imóveis ativos com informação confirmada nos últimos 30 dias (% do catálogo) | CRM, campo "data da última confirmação" | Rayssa | Semanal |
| 10 | Corretores parceiros ativos (agendaram pelo menos 1 visita no mês) | CRM / agenda de visitas | Rayssa | Mensal, com contagem semanal |

Campos obrigatórios em cada negócio no CRM (sem eles não dá para calcular lucro):
- Quem atende: Tel / corretor da casa / parceiro
- Imóvel próprio ou de parceiro
- Teve SDR: sim / não

## 5. Riscos apontados
- Montar sistema de métrica em vez de vender. Preenchimento não pode passar de 30 minutos por semana; Pedro deve puxar 1, 3, 4 e 8 direto do CRM.
- HIPÓTESE (não confirmada): se o ciclo do primeiro contato até a assinatura for de algumas semanas, lead que entrar depois de meados de novembro não assina até 27/12. Os 2 negócios já fechados respondem isso.
- Venda financiada: promessa assinada com crédito não aprovado pode cair. Marcar esses negócios como "risco de crédito" no pipeline.
- Semana da mudança (27/10) tende a ser fraca e já está dentro das 9,7 semanas.

## 6. Dados que ainda faltam (pendentes do Tel)
1. Lista de negócios em andamento hoje: imóvel, valor, % de comissão, quem atende, imóvel próprio ou de parceiro, tem SDR, etapa (visita feita / proposta / análise de crédito), data prevista de assinatura.
2. Últimos 7 dias: leads por origem, visitas realizadas, propostas, contratos assinados.
3. Gasto de tráfego da semana, se estiver rodando.
4. Alíquota de imposto efetiva sobre comissão (contador) e se a meta de R$200 mil é antes ou depois de imposto.
5. Os 2 negócios fechados: data do primeiro contato e data da assinatura. E a % de comissão da venda de R$720 mil.
6. Pedro: o CRM já registra origem do lead, horário da primeira resposta e etapa do negócio? Se não, quanto tempo para criar.
7. Quantos SDRs já estão trabalhando de fato (não vagas abertas).
8. Quantos imóveis ativos tem o catálogo hoje.

## 7. Ações desta semana
1. Tel monta a lista de negócios em andamento (item 1 da seção 6). Cerca de 1 hora.
2. Pedro cria no CRM o campo "origem" e os 3 campos obrigatórios.
3. Tel envia os 8 dados pendentes para calcular o gargalo número 1 e a projeção até 27/12.

## RESUMO PARA ESTRATÉGIA
- Meta pede cerca de 16 contratos em 9,7 semanas (1,65 por semana); ritmo histórico é cerca de 0,3 por semana, 5 vezes menor.
- Lucro por contrato varia de R$6.531 (25%) a R$26.125 (100%) conforme quem fecha e de quem é o imóvel.
- Problema número 1 agora: não existe pipeline medido, então não dá para saber se a meta é viável.
- Decisão: priorizar a agenda do Tel como corretor a partir de 27/10 e direcionar os SDRs para imóveis do catálogo próprio.
- Pendente: impostos, ciclo de venda e lista de negócios em andamento.
