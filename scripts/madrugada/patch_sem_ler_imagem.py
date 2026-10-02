#!/usr/bin/env python3
"""A NAY NÃO LÊ MAIS IMAGEM (Pedro, 01/10/2026).

"agora não lemos mais imagens, o que for imagem de imóvel é salva só, não quero
que a IA leia imagem mais, pode desativar esses nós."

O RAMO: Reservar mensagens -> Detectar imagem -> Baixar imagem -> Montar leitura
da imagem -> Ler imagem (GPT) -> Juntar mensagens.

A ARMADILHA, e por que este arquivo não marca `disabled` nos nós:

  1. No n8n, nó DESATIVADO não para o dado: ele PASSA a entrada adiante. Marcar
     "Detectar imagem" como desativado jogaria os itens crus do webhook dentro
     de "Juntar mensagens" pelo caminho do ramo -- a mesma classe de erro que
     quebrou o "Abrir turno" às 12:41 de 16/09.
  2. Quem decide esperar a leitura é o "Juntar mensagens", pelo WEBHOOK, não
     pelos nós: `if (vaiLerImagem && rodou('Ler imagem (GPT)').itens === 0)
     return []`. Só cortar a ligação faria o turno NUNCA abrir para quem manda
     foto -- a Nay ficaria muda com toda imagem, de uma vez.

Então o desligamento é por dentro, nos dois pontos que importam:
  a) "Detectar imagem" devolve [] na primeira linha: não baixa, não chama a
     OpenAI, não gasta. O ramo morre aí, do mesmo jeito que já morria quando a
     mensagem não tinha imagem (o caso comum).
  b) "Juntar mensagens" não espera mais leitura nenhuma.

O QUE A NAY PASSA A FAZER (nenhum caminho novo; os dois já existem e rodam):
  * foto COM texto -> ela responde o texto e ignora a foto;
  * foto SEM texto (186 de 189 imagens da semana) -> cai no envelope que já
    existe para mídia que ela não abriu: uma linha curta avisando que recebeu e
    `escalar_ao_tel`, a regra do Tel de 16/09 ("ela NUNCA deve falar que não lê
    imagem; se não conseguir, manda a imagem ao Tel").

A FOTO CONTINUA SALVA: `midia_url` é gravado em "Filtrar e normalizar" e
"Gravar na fila", fora deste ramo.

Uso: patch_sem_ler_imagem.py <export.json> <saida.json>
Falha (exit 1) sem escrever nada se uma âncora não bater. Sai 0 dizendo "nada a
fazer" onde o ramo não existe (a VPS da captação), para o script da madrugada
servir nas duas sem ramo especial.
"""
import json
import sys

MATA = ("// 01/10/2026: A NAY NAO LE MAIS IMAGEM (Pedro). Este no para aqui: nao\n"
        "// baixa a foto e nao chama a OpenAI. NAO marque este no como desativado --\n"
        "// no n8n o no desativado PASSA o dado adiante, e isso jogaria o item cru\n"
        "// dentro do \"Juntar mensagens\". Ver scripts/madrugada/patch_sem_ler_imagem.py.\n"
        "return [];\n")

DE_ESPERA = ("const vaiLerImagem   = !midiaDaqui && "
             "(!!urlImg || (!!urlDoc && /pdf|image/i.test(mimeDoc)));")
PARA_ESPERA = ("// 01/10/2026: NAO LEMOS MAIS IMAGEM (Pedro), entao nao ha leitura a esperar.\n"
               "// Deixar `true` aqui com o ramo desligado faria o turno nunca abrir para quem\n"
               "// manda foto: a Nay ficaria muda com toda imagem.\n"
               "const vaiLerImagem   = false;")


def no(fluxo, nome):
    for n in fluxo.get('nodes', []):
        if n.get('name') == nome:
            return n
    return None


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    entrada, saida = sys.argv[1], sys.argv[2]
    with open(entrada, encoding='utf-8') as f:
        dados = json.load(f)
    fluxos = dados if isinstance(dados, list) else [dados]

    alvo = None
    for fluxo in fluxos:
        if no(fluxo, 'Detectar imagem') and no(fluxo, 'Juntar mensagens'):
            alvo = fluxo
            break
    if alvo is None:
        # a VPS da captação não tem o ramo da imagem: não é erro, é não ter o que fazer
        print('este n8n não tem o ramo da imagem: nada a fazer')
        return 0

    det = no(alvo, 'Detectar imagem')
    jun = no(alvo, 'Juntar mensagens')

    codigo = det.get('parameters', {}).get('jsCode')
    if not isinstance(codigo, str) or not codigo.strip():
        print('"Detectar imagem" não tem jsCode: nada mudou')
        return 1
    if codigo.startswith(MATA):
        print('"Detectar imagem" já estava parado')
    else:
        det['parameters']['jsCode'] = MATA + codigo

    espera = jun.get('parameters', {}).get('jsCode')
    if not isinstance(espera, str):
        print('"Juntar mensagens" não tem jsCode: nada mudou')
        return 1
    if PARA_ESPERA in espera:
        print('"Juntar mensagens" já não esperava a leitura')
    else:
        vezes = espera.count(DE_ESPERA)
        if vezes != 1:
            print('a linha da espera da imagem apareceu %d vez(es) em "Juntar mensagens", '
                  'esperava 1 -- o fluxo vivo está diferente do esperado: nada mudou' % vezes)
            return 1
        jun['parameters']['jsCode'] = espera.replace(DE_ESPERA, PARA_ESPERA)

    # confere o resultado antes de escrever
    novo_det = det['parameters']['jsCode']
    novo_jun = jun['parameters']['jsCode']
    if not novo_det.startswith(MATA) or PARA_ESPERA not in novo_jun:
        print('a conferência final falhou: nada escrito')
        return 1
    if 'vaiLerImagem' not in novo_jun or novo_jun.count('vaiLerImagem') != 2:
        print('"vaiLerImagem" deveria aparecer 2 vezes em "Juntar mensagens": nada escrito')
        return 1

    with open(saida, 'w', encoding='utf-8') as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)
    print('leitura de imagem desligada em "%s"; patch em %s' % (alvo.get('name'), saida))
    return 0


if __name__ == '__main__':
    sys.exit(main())
