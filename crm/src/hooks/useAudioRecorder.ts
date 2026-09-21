import { useRef, useState, useCallback, useEffect } from 'react'

const MIME_CANDIDATES = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4']

function pickMimeType(): string | undefined {
  if (typeof MediaRecorder === 'undefined') return undefined
  return MIME_CANDIDATES.find((type) => MediaRecorder.isTypeSupported(type))
}

export function useAudioRecorder() {
  const [isRecording, setIsRecording] = useState(false)
  const [durationMs, setDurationMs] = useState(0)
  const mediaRecorderRef = useRef<MediaRecorder | null>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const chunksRef = useRef<Blob[]>([])
  const startedAtRef = useRef(0)
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const cleanupStream = useCallback(() => {
    streamRef.current?.getTracks().forEach((track) => track.stop())
    streamRef.current = null
    if (intervalRef.current) clearInterval(intervalRef.current)
    intervalRef.current = null
  }, [])

  useEffect(() => cleanupStream, [cleanupStream])

  const start = useCallback(async () => {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    streamRef.current = stream
    chunksRef.current = []

    const mimeType = pickMimeType()
    const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined)
    recorder.ondataavailable = (e) => {
      if (e.data.size > 0) chunksRef.current.push(e.data)
    }
    mediaRecorderRef.current = recorder
    recorder.start()

    startedAtRef.current = Date.now()
    setDurationMs(0)
    setIsRecording(true)
    intervalRef.current = setInterval(() => {
      setDurationMs(Date.now() - startedAtRef.current)
    }, 250)
  }, [])

  const stop = useCallback((): Promise<Blob> => {
    return new Promise((resolve, reject) => {
      const recorder = mediaRecorderRef.current
      if (!recorder) {
        reject(new Error('Nenhuma gravação em andamento.'))
        return
      }
      recorder.onstop = () => {
        const mimeType = recorder.mimeType || 'audio/webm'
        const blob = new Blob(chunksRef.current, { type: mimeType })
        cleanupStream()
        setIsRecording(false)
        resolve(blob)
      }
      recorder.stop()
    })
  }, [cleanupStream])

  const cancel = useCallback(() => {
    mediaRecorderRef.current?.stop()
    cleanupStream()
    setIsRecording(false)
    setDurationMs(0)
    chunksRef.current = []
  }, [cleanupStream])

  return { isRecording, durationMs, start, stop, cancel }
}
