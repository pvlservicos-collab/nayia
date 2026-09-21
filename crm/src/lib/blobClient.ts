/**
 * Upload de arquivos direto do navegador para o Vercel Blob.
 *
 * Por quê: Vercel Functions têm um limite rígido de 4.5MB no corpo da requisição
 * (plataforma, não configurável). O antigo fluxo mandava o arquivo inteiro por
 * FormData pro endpoint /api/upload, que por sua vez repassava pro Blob — então
 * qualquer vídeo (quase sempre >4.5MB) ou foto de celular um pouco maior já
 * chegava rejeitado (413) antes mesmo do nosso código rodar. A correção oficial
 * da Vercel pra esse limite é o upload direto cliente→Blob: o navegador manda os
 * bytes direto pro storage, e o servidor só emite um token de autorização de
 * curta duração (handleUpload em /api/upload).
 *
 * https://vercel.com/kb/guide/how-to-bypass-vercel-body-size-limit-serverless-functions
 */
'use client'

import { upload } from '@vercel/blob/client'

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
 * Envia um arquivo direto pro Vercel Blob e retorna a URL pública.
 * Substitui o antigo `fetch('/api/upload', { body: formData })`.
 */
export async function uploadClientFile(file: File, folder: UploadFolder, identifier: string): Promise<string> {
  const normalized = await normalizeImageOrientation(file)
  const ext = normalized.name.split('.').pop() || 'bin'
  const pathname = `${folder}/${identifier}_${Date.now()}.${ext}`

  const blob = await upload(pathname, normalized, {
    access: 'public',
    contentType: normalized.type || 'application/octet-stream',
    handleUploadUrl: '/api/upload',
  })

  return blob.url
}
