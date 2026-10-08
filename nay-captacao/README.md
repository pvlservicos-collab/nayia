# nay-captacao: a Nay de captação em Python

Pedro, 08/10/2026: "prepara a nay captação para rodar no número de api oficial, mas já sabendo a resposta do
modelo situacao_imovel_cadastrado_1 ... pode recriar a nay de captação em python sem perder nada ... e quero mais
uma pergunta no fluxo dela, se [ele] tem alguém que esteja vendendo um imóvel para indicar ... por enquanto roda só
no meu número".

## O que é

O serviço que decide e responde as conversas da captação de proprietários **pelo número oficial** (8456-0874), no
lugar do agente do fluxo do n8n (`Nay - captacao proprietarios`, VPS2). Roda no srv1894338, em
`/root/nay-captacao`, como o serviço systemd `nay-captacao`.

## O que veio do fluxo, peça por peça

| no n8n | aqui |
|---|---|
| Janela de 20s + Reservar mensagens | `banco.FILA`, `banco.RESERVAR` |
| Juntar mensagens | `turno.juntar` |
| AI Agent (texto do turno) | `turno.cabecalho` |
| AI Agent + GPT (captação) + Memoria | `modelo.responder` (API de Responses; a conversa vem de `captacao_mensagens`) |
| as 6 ferramentas (SQL) | `ferramentas.json`, tirado do fluxo por `scripts/extrair_ferramentas.py` |
| escalar_ao_tel (sub-fluxo) | `ferramentas.executar` + `banco.ESCALAR` |
| Preparar resposta | `resposta.baloes` |
| Pausa, Ainda é da IA? | `atender.atender` + `banco.AINDA_E_DA_IA` |
| Enviar resposta (oficial) | `envio.texto` (pelo CRM) |
| Registrar saida | `banco.REGISTRAR_SAIDA` |
| Registrar envio | `banco.REGISTRAR_DISPARO` |

O prompt é o MESMO, o vivo do banco (`nai_prompt_de('captacao')`), com um acréscimo que só vale aqui
(`modelo.ACRESCIMO`): o modelo da Meta que abriu a conversa, com os três botões, e a pergunta da indicação.

## O que é novo

- **O modelo que abre a conversa**: `situacao_imovel_cadastrado_1` (pt_BR), com os botões Disponível / Alugado /
  Vendido. `python -m captacao.disparo --lead N` manda e registra. O toque no botão chega como texto e é a resposta
  da situação.
- **A indicação**: antes de encerrar ela pergunta se a pessoa conhece alguém vendendo um imóvel. É parede:
  `encerrar_conversa` não encerra enquanto a pergunta não saiu (`captacao_indicacao_pendente`). O indicado fica em
  `privado.captacao_indicacao` (ferramenta `guardar_indicacao`).

## O que AINDA é do fluxo do n8n

- A **entrada**: o webhook do número oficial, a transcrição do áudio, a foto guardada na ficha e o "Gravar na
  fila". A mensagem entra por lá; o gatilho da migração 315 marca como `Recebido py` as dos telefones da lista, e
  só essas chegam aqui.
- O **disparo em massa**, o lembrete, o vigia do número e o relatório das 18h.
- Toda conversa de quem **não está na lista**.

## Quem é atendido aqui

`captacao_config.python_telefones`: telefones separados por vírgula (`todos` = todos). Hoje, só o número do Pedro.
Tirar um número da lista devolve o número ao fluxo antigo na mensagem seguinte.

## Rodar

```
systemctl status nay-captacao            journalctl -u nay-captacao -n 50
cd /root/nay-captacao && set -a && . ./.env && set +a
.venv/bin/python -m captacao.ensaio disponivel     # conversa inteira com o lead de teste; nada sai, nada fica
.venv/bin/python -m captacao.disparo --lead 835 --zerar   # manda o modelo de verdade ao lead de teste
python -m unittest discover -s tests               # as partes puras (roda em qualquer máquina)
```

`.env` (fora do git): `DATABASE_URL`, `OPENAI_API_KEY`, `CAPTACAO_OFICIAL_SEGREDO`; opcionais `CAPTACAO_AVISAR_TEL`
(`nao` enquanto é teste: escalada e foto ficam gravadas, mas o Tel não recebe aviso) e `CAPTACAO_MODELO`.

## Parar

`systemctl stop nay-captacao` e esvaziar `python_telefones`. Com a lista vazia nada chega aqui.
