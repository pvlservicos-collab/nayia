/**
 * Upload de arquivos do navegador para o armazém do CRM (29/09/2026).
 *
 * Até 28/09 o navegador mandava direto para o Vercel Blob, com um token que
 * /api/upload emitia -- o Blob não existe neste servidor, e todo anexo quebrava
 * ("Vercel Blob: No token found"). O limite de 4,5MB que motivou aquilo era da
 * Vercel. Agora o arquivo vai inteiro para /api/upload, que guarda no disco do
 * servidor (src/lib/armazem.ts) e devolve o endereço /api/midia/...
 */
'use client'

export type UploadFolder = 'avatars' | 'org-logos' | 'chat-media' | 'feature-screenshots'

// Mesmos tipos cobertos pelo antigo normalizeImageOrientation() do servidor (agora feito
// aqui no cliente, já que o arquivo não passa mais pelo nosso backend antes do upload).
const ROTATABLE_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp']

/**
 * Corrige o "grava deitado, mostra em pé" clássico de foto de celular: a câmera grava a
 * tag EXIF de orientação em vez de rotacionar os pixels, e o navegador aplica essa tag ao
 * exibir — mas serviços que baixam a imagem depois (Evolution API, WhatsApp) podem não
 * respeitar essa tag. Decodificar respeitando a orientação e redesenhar em canvas grava os
 * pixels já corretos, sem tag, garantindo exibição correta em qualquer lugar.
 */
async function normalizeImageOrientation(file: File): Promise<File> {
  if (!ROTATABLE_IMAGE_TYPES.includes(file.type)) return file
  try {
    const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
    const canvas = document.createElement('canvas')
    canvas.width = bitmap.width
    canvas.height = bitmap.height
    const ctx = canvas.getContext('2d')
    if (!ctx) return file
    ctx.drawImage(bitmap, 0, 0)
    bitmap.close()

    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, file.type))
    if (!blob) return file
    return new File([blob], file.name, { type: file.type })
  } catch (err) {
    console.error('[upload] Falha ao normalizar orientação EXIF, enviando arquivo original:', err)
    return file
  }
}

/**
 * Manda o arquivo para o armazém do CRM e devolve o endereço (/api/midia/...).
 * Mesma assinatura de antes: quem chama não muda.
 */
export async function uploadClientFile(file: File, folder: UploadFolder, identifier: string): Promise<string> {
  const normalized = await normalizeImageOrientation(file)
  const form = new FormData()
  form.append('arquivo', normalized, normalized.name || file.name || 'arquivo')
  form.append('pasta', folder)
  form.append('id', identifier)

  const res = await fetch('/api/upload', { method: 'POST', body: form })
  const corpo = await res.json().catch(() => ({} as Record<string, unknown>))
  if (!res.ok || typeof corpo.url !== 'string') {
    throw new Error(String(corpo.error || `Falha ao enviar o arquivo (HTTP ${res.status})`))
  }
  return corpo.url
}
