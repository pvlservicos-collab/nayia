"""CAPTAÇÃO: FOTO SOZINHA NÃO PARA O ATENDIMENTO (Pedro, 03/10/2026).

"quando ele reconhece imagens ele pode avisar o Tel mas deve continuar o atendimento com as perguntas dele como
se ignorasse imagem, avisasse o Tel mas voltasse a fazer as perguntas do cadastro" / "cuidado para ele nunca
dizer para o cliente que não consegue ver as imagens, só salvar" / "e continuar o atendimento".

Até aqui (02/10) o lote SÓ de fotos não virava turno: a foto ia para a ficha, o Tel era avisado e a Nay ficava
calada -- e a conversa parava ali, porque ninguém fazia a pergunta seguinte. Agora:

1. `Reservar mensagens` devolve `ja_seguiu_depois_de_foto`: ela já respondeu depois de fotos que ele mandou desde
   a última mensagem ESCRITA dele? (lotes anteriores; o lote atual ainda aparece como 'Recebido' no snapshot)
2. `Juntar mensagens`: lote só de foto, primeira vez na rodada de fotos -> vira turno com a instrução de NÃO
   comentar a foto e seguir a pergunta do cadastro (ficha aberta: guardar_ficha com fotos = "recebidas" e a
   pergunta que ela devolver; "Recebi, obrigada!" só se a pergunta pendente era a das fotos). Lotes seguintes da
   mesma rodada continuam calados (em 02/10 ela agradeceu 20 fotos, uma a uma). O aviso ao Tel continua.
3. `Preparar resposta`: parede -- frase dizendo que não consegue ver/abrir/receber imagem, foto, arquivo ou vídeo
   NÃO sai, mesmo que o modelo escreva (saiu 4 vezes até 15/09).

Uso: python3 patch_captacao_imagem_continua.py <export.json> <saida.json>
Sai 1 sem escrever nada se qualquer âncora não bater (o fluxo mudou: olhar antes de aplicar).
"""
import json
import re
import sys

FLUXO = "CjsUJefRYcQIIi1F"


def trocar(texto, velho, novo, onde):
    if texto.count(velho) != 1:
        raise SystemExit(f"âncora não bateu em {onde} ({texto.count(velho)}x): {velho[:70]!r}")
    return texto.replace(velho, novo)


SEG = """WITH seg AS (
  -- 03/10: ela ja seguiu o atendimento depois de fotos que ele mandou desde a ultima mensagem ESCRITA dele?
  -- Os lotes anteriores ja estao processados; o lote desta execucao ainda aparece como 'Recebido' (o UPDATE do
  -- `res` nao e visto pelas outras partes do comando). Lote so de foto continua o atendimento uma vez por
  -- rodada de fotos, nao a cada lote.
  SELECT EXISTS (
    SELECT 1 FROM captacao_mensagens e
     WHERE nay_fone_chave(e.telefone) = nay_fone_chave($1::text) AND e.direcao = 'enviada'
       AND e.criada_em > (
         SELECT min(i.criada_em) FROM captacao_mensagens i
          WHERE nay_fone_chave(i.telefone) = nay_fone_chave($1::text)
            AND i.direcao = 'recebida' AND i.origem = 'imagem' AND i.status <> 'Recebido'
            AND i.criada_em > coalesce((SELECT max(t.criada_em) FROM captacao_mensagens t
                                         WHERE nay_fone_chave(t.telefone) = nay_fone_chave($1::text)
                                           AND t.direcao = 'recebida' AND t.origem <> 'imagem'
                                           AND t.status <> 'Recebido'), '-infinity'::timestamptz))) AS ja
), tel AS ("""

CONTINUA = """const soImagem = !texto && naoTexto.length > 0 && naoTexto.every(o => o === 'imagem');
// ...MAS O ATENDIMENTO CONTINUA (Pedro, 03/10/2026: "pode avisar o Tel, mas deve continuar o atendimento com as
// perguntas dele como se ignorasse a imagem" / "nunca dizer para o cliente que nao consegue ver as imagens, so
// salvar"). Lote so de foto: ela nao comenta a foto e segue com a pergunta do cadastro. Uma vez por rodada de
// fotos: se ela ja seguiu depois de fotos anteriores e ele nao escreveu nada desde entao, este lote fica calado
// (em 02/10 ela agradeceu 20 fotos, uma a uma). A foto ja foi salva pelo ramo 'Foto do dono?'.
const jaSeguiu = itens.some(m => m.ja_seguiu_depois_de_foto === true);
const seguirSemFoto = soImagem && !jaSeguiu;
const escreveu = itens.some(m => val(m));
if (seguirSemFoto) {
  texto = '(ele mandou so foto' + (itens.length > 1 ? 's' : '') + ' do imovel, sem escrever nada. As fotos ja'
        + ' foram salvas do nosso lado -- isso e informacao sua, nao fale disso. '
        + (fichaAberta
           ? 'Chame guardar_ficha com fotos = "recebidas" e faca a pergunta que ela devolver. Se a pergunta que'
             + ' estava pendente era justamente a das fotos, diga antes so "Recebi, obrigada!"; senao, nao fale'
             + ' das fotos.'
           : 'Nao fale das fotos: continue o atendimento de onde parou, refazendo em uma linha a ultima pergunta'
             + ' que ficou sem resposta (ou a proxima do roteiro).')
        + ' NAO diga que nao consegue ver ou abrir imagem, NAO diga que nao recebeu, NAO peca para ele descrever'
        + ' a foto e NAO fale de sistema.)';
}
"""

AVISO_VELHO = re.compile(
    r"\+ \(soImagem \? '\\n\\nEla nao respondeu: imagem sozinha ela ignora\.'\s*"
    r":\s*'\\n\\nEla agradeceu e seguiu o roteiro, sem dizer que nao conseguia ver\.'\);")
AVISO_NOVO = ("+ (seguirSemFoto ? '\\n\\nEla nao comentou a foto e seguiu com as perguntas do cadastro.'\n"
              "               : soImagem ? '\\n\\nEla nao respondeu: ja tinha seguido o atendimento depois das"
              " fotos anteriores.'\n"
              "               : escreveu ? '\\n\\nEla seguiu o atendimento sem comentar a foto.'\n"
              "               : '\\n\\nEla agradeceu e seguiu o roteiro, sem dizer que nao conseguia ver.');")

PAREDE = """// NUNCA DIZ QUE NAO VE A IMAGEM (Pedro, 03/10/2026: "cuidado para ele nunca dizer para o cliente que nao
// consegue ver as imagens, so salvar"). Saiu 4 vezes ate 15/09 ("nao consigo abrir a imagem por aqui"). O prompt
// e a instrucao do turno ja proibem; isto e a garantia: a frase sai antes de enviar.
const NAO_VE = /\\bn[aã]o\\s+(consigo|consegui|d[aá]\\s+(pra|para)|posso|estou conseguindo|t[oô] conseguindo)\\s+(ver|abrir|visualizar|enxergar|baixar|carregar|ler|ouvir)\\b|\\b(imagens?|fotos?|arquivos?|v[ií]deos?|anexos?)\\s+n[aã]o\\s+(abr\\w*|carreg\\w*|apar\\w*|cheg\\w*|vei[ao]|vieram)|\\bn[aã]o\\s+(vejo|enxergo|recebi)\\s+(a|as|o|os|sua|suas|seu|seus)?\\s*(imagens?|fotos?|arquivos?|v[ií]deos?)/i;
function semNaoVe(texto) {
  const prot = texto.replace(/\\b(Sr|Sra|Dr|Dra|Srta)\\./g, '$1\\u0001');
  return prot.split(/(?<=[.!?])\\s+|\\n+/)
    .filter(f => f.trim() && !NAO_VE.test(f.replace(/\\u0001/g, '.')))
    .join(' ').replace(/\\u0001/g, '.').trim();
}
const bruto2 ="""


def main(entrada: str, saida: str) -> None:
    dados = json.load(open(entrada, encoding="utf-8"))
    fluxos = dados if isinstance(dados, list) else [dados]
    alvo = [w for w in fluxos if w.get("id") == FLUXO]
    if len(alvo) != 1:
        raise SystemExit(f"fluxo {FLUXO} não está no export")
    nos = {n["name"]: n for n in alvo[0]["nodes"]}
    for nome in ("Reservar mensagens", "Juntar mensagens", "Preparar resposta"):
        if nome not in nos:
            raise SystemExit(f"nó {nome!r} sumiu do fluxo")

    q = nos["Reservar mensagens"]["parameters"]["query"]
    if "ja_seguiu_depois_de_foto" in q:
        raise SystemExit("já aplicado: nada a fazer")
    q = trocar(q, "WITH tel AS (", SEG, "Reservar mensagens")
    q = trocar(q, "       captacao_ficha_aviso(l.id) AS ficha,",
               "       (SELECT ja FROM seg) AS ja_seguiu_depois_de_foto,\n"
               "       captacao_ficha_aviso(l.id) AS ficha,", "Reservar mensagens")
    nos["Reservar mensagens"]["parameters"]["query"] = q

    js = nos["Juntar mensagens"]["parameters"]["jsCode"]
    js = trocar(js, "const soImagem = !texto && naoTexto.length > 0 && naoTexto.every(o => o === 'imagem');\n",
                CONTINUA, "Juntar mensagens")
    if len(AVISO_VELHO.findall(js)) != 1:
        raise SystemExit("âncora do aviso ao Tel não bateu em Juntar mensagens")
    js = AVISO_VELHO.sub(lambda _: AVISO_NOVO, js)
    js = trocar(js, "if (soImagem) return [];", "if (soImagem && !seguirSemFoto) return [];", "Juntar mensagens")
    nos["Juntar mensagens"]["parameters"]["jsCode"] = js

    pr = nos["Preparar resposta"]["parameters"]["jsCode"]
    pr = trocar(pr, "const bruto2 =", PAREDE, "Preparar resposta")
    pr = trocar(pr, ".map(semPromessa).filter(Boolean)", ".map(semPromessa).map(semNaoVe).filter(Boolean)",
                "Preparar resposta")
    nos["Preparar resposta"]["parameters"]["jsCode"] = pr

    json.dump(alvo, open(saida, "w", encoding="utf-8"), ensure_ascii=False)
    print("patch ok:", saida)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
