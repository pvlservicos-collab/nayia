# nay-grupos: captação ativa por grupos

Lê os pedidos que os corretores fazem nos grupos de WhatsApp ("procuro apartamento 2 quartos no Adrianópolis
até 4 mil"), compara com o nosso catálogo e dá uma nota de 0 a 100. Aparece no admin do site, em
**Grupos › Captação ativa** (ao lado de Métricas).

Pedido do Pedro em 09/10/2026. **O serviço lê, extrai, pontua e mostra. Não envia nada sozinho**, e não tem por
onde enviar (`grupos/envio.py` só levanta erro). O envio automático (modo ativo) vem depois do sim dele.

O que existe é o **envio manual** (pedido dele na noite de 09/10): o botão "Enviar ao corretor" de cada pedido abre a
conferência com a mensagem padrão e, no clique dele, o banco (`site_captacao_grupos_enviar`, migração 339) põe a
abertura, o card e as fotos na caixa de saída da Nay, pelo número da Parceria. `envio_manual: false` no `config.json`
desliga o botão e a função.

## Como roda

Serviço em Python na VPS1, no molde do `nay-captacao`:

    /root/nay-grupos            o código (esta pasta)
    /root/nay-grupos/.env       DATABASE_URL, OPENAI_API_KEY (fora do git)
    systemctl status nay-grupos
    journalctl -u nay-grupos -f

A cada 10 s: relê `config.json`, lê as mensagens novas (as do grupo e as coladas na tela), passa cada uma pela
IA (`gpt-6-luna`), reconhece bairro e condomínio, filtra, pontua e grava. De 10 em 10 minutos refaz a conta da
janela inteira (o catálogo muda).

## De onde vêm as mensagens

`privado.grupo_conversa`, que o webhook do CRM alimenta com o que a Z-API entrega dos grupos da Parceria.
**Em 09/10 a Z-API não entregava o texto dos grupos** (só avisos de entrou/saiu/apagou): enquanto isso não for
ligado na instância, só chegam aqui as mensagens coladas na tela ("Testar uma mensagem").

## O que ele ajusta sem mexer no código

`config.json`: modo, envio manual (liga/desliga, a mensagem de abertura, o intervalo por corretor, se vão card e
fotos), janela (48 h), pesos, cortes (90 e 70), faixas de preço, quanto vale o bairro próximo (cai com a distância:
quem faz divisa vale mais; sem divisa só até 5 km), um quarto a mais e semi-mobiliado, dias de confirmação,
alternativas, teto de leituras da IA por dia. O serviço relê sozinho. Valor torto ou arquivo
estragado: vale o padrão (`grupos/regras.py`) e o aviso aparece na tela.

Apelidos de bairro e condomínio: na própria aba (tabela `privado.grupo_apelido`).
Bairros vizinhos: tabela `bairro_vizinho` (admin › tabelas do banco) mais os que fazem divisa no mapa
(`geo_bairro_vizinho`).

## As partes

| arquivo | o que faz |
|---|---|
| `grupos/extrair.py` | passo 1: o prompt, o esquema do JSON e a limpeza do que a IA devolve |
| `grupos/lugares.py` | do nome escrito ao nome do cadastro (apelidos, conjuntos, o mais parecido) |
| `grupos/catalogo.py` | os imóveis nossos disponíveis, a data de confirmação e os vizinhos |
| `grupos/pontuar.py` | passos 2 a 4: filtros, nota e faixa (só conta; é o que os testes cobrem) |
| `grupos/worker.py` | o laço do serviço |
| `grupos/envio.py` | o envio, que nesta versão não existe |
| `grupos/regras.py` | lê e confere o `config.json` |

Banco: migração 336 (tabelas `privado.grupo_pedido*`, `privado.grupo_apelido`, `privado.grupo_captacao_estado`
e as funções `site_captacao_grupos*` que a tela chama pela `/admin/api/grupos/captacao`).

## Testar

    python -m unittest discover -s tests            a conta, sem banco nem rede
    .venv/bin/python scripts/provar_extracao.py --conta      (no servidor) as 4 mensagens do Pedro com a IA de verdade
