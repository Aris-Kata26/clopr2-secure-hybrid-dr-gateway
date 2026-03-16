import { useState, useEffect, useRef } from 'react'
import { motion } from 'framer-motion'

function highlightLogLine(line) {
  const esc = line.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
  return esc
    .replace(/\b(PASS|COMPLETE|HEALTHY|streaming)\b/g,'<span style="color:#4ade80;font-weight:700">$1</span>')
    .replace(/\b(FAIL|FAILED|ERROR|ABORTED)\b/g,'<span style="color:#f87171;font-weight:700">$1</span>')
    .replace(/\[DRY-RUN\]/g,'<span style="color:#fbbf24;font-weight:700">[DRY-RUN]</span>')
    .replace(/(\d{4}-\d{2}-\d{2}T[\d:Z.]+)/g,'<span style="color:#64748b">$1</span>')
    .replace(/(STEP \d+|FS-\d+|FB-\d+|S-\d+|P-\d+|H-\d+|B-\d+)/g,'<span style="color:#7dd3fc;font-weight:600">$1</span>')
    .replace(/(\[[\w\-]+\s+\d{4}-\d{2}-\d{2}T[^\]]+\])/g,'<span style="color:#475569">$1</span>')
    .replace(/(RTO|RPO):\s*([\w\s]+)/g,'<span style="color:#a78bfa;font-weight:700">$1: $2</span>')
}

export default function LogStream({ runId, onComplete }) {
  const [lines, setLines] = useState([])
  const [done, setDone] = useState(false)
  const [result, setResult] = useState(null)
  const [scrollLock, setScrollLock] = useState(true)
  const [elapsed, setElapsed] = useState(0)
  const scrollRef = useRef(null)
  const startRef = useRef(Date.now())
  const esRef = useRef(null)

  // Elapsed timer
  useEffect(() => {
    if (done) return
    const id = setInterval(() => setElapsed(Math.floor((Date.now() - startRef.current) / 1000)), 500)
    return () => clearInterval(id)
  }, [done])

  // SSE connection
  useEffect(() => {
    if (!runId) return
    startRef.current = Date.now()
    setLines([])
    setDone(false)
    setResult(null)

    const es = new EventSource(`/api/run/${runId}/stream`)
    esRef.current = es

    es.onmessage = (e) => {
      try {
        const { line } = JSON.parse(e.data)
        setLines(prev => [...prev, line])
      } catch {}
    }

    es.addEventListener('done', (e) => {
      try {
        const res = JSON.parse(e.data)
        setResult(res)
        setDone(true)
        onComplete?.(res)
      } catch {}
      es.close()
    })

    es.onerror = () => {
      setLines(prev => [...prev, '[stream-error] Connection lost'])
      setDone(true)
      es.close()
    }

    return () => { es.close() }
  }, [runId])

  // Auto-scroll
  useEffect(() => {
    if (scrollLock && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [lines, scrollLock])

  const passed  = result?.status === 'passed' || result?.exit_code === 0
  const failed  = result?.status === 'failed' || (result?.exit_code !== undefined && result.exit_code !== 0)

  return (
    <div className="rounded-xl border border-white/8 overflow-hidden"
         style={{ background: '#050c18' }}>
      {/* Toolbar */}
      <div className="flex items-center justify-between px-4 py-2 border-b border-white/5"
           style={{ background: 'rgba(17,24,39,0.8)' }}>
        <div className="flex items-center gap-3">
          {!done ? (
            <span className="flex items-center gap-1.5 text-xs text-sky-400">
              <span className="w-2 h-2 rounded-full bg-sky-400 animate-pulse" />
              Running…
            </span>
          ) : passed ? (
            <span className="flex items-center gap-1.5 text-xs font-bold text-emerald-400">
              <span className="w-2 h-2 rounded-full bg-emerald-400" />
              PASSED
            </span>
          ) : (
            <span className="flex items-center gap-1.5 text-xs font-bold text-red-400">
              <span className="w-2 h-2 rounded-full bg-red-400" />
              FAILED
            </span>
          )}
          <span className="text-xs font-mono text-slate-500">
            {done ? `${elapsed}s elapsed` : `${elapsed}s`}
          </span>
          <span className="text-xs text-slate-600">{lines.length} lines</span>
        </div>
        <button
          onClick={() => setScrollLock(l => !l)}
          className={`text-xs px-2 py-0.5 rounded border transition-colors ${
            scrollLock ? 'border-sky-700 text-sky-400' : 'border-white/10 text-slate-500'
          }`}
        >
          {scrollLock ? '⬇ auto-scroll' : '⏸ paused'}
        </button>
      </div>

      {/* Log lines */}
      <div ref={scrollRef} className="h-72 overflow-y-auto p-4 font-mono text-xs"
           style={{ fontFamily: "'JetBrains Mono', 'Fira Code', monospace" }}>
        {lines.length === 0 && !done && (
          <span className="text-slate-600">Waiting for output…</span>
        )}
        {lines.map((line, i) => (
          <div key={i} className="leading-relaxed py-0.5"
               dangerouslySetInnerHTML={{ __html: highlightLogLine(line) }} />
        ))}
      </div>

      {/* Result banner */}
      {done && (
        <motion.div
          initial={{ opacity: 0, y: 4 }}
          animate={{ opacity: 1, y: 0 }}
          className={`flex items-center gap-4 px-5 py-3 border-t ${
            passed
              ? 'border-emerald-900/40 bg-emerald-950/40'
              : 'border-red-900/40 bg-red-950/40'
          }`}
        >
          <span className={`text-2xl font-extrabold ${passed ? 'text-emerald-400' : 'text-red-400'}`}>
            {passed ? '✅ PASS' : '❌ FAIL'}
          </span>
          <div className="text-xs text-slate-400">
            <span className="font-mono">exit {result?.exit_code ?? '?'}</span>
            <span className="mx-2">·</span>
            <span>{elapsed}s elapsed</span>
            {result?.finished_at && (
              <><span className="mx-2">·</span><span className="text-slate-500">{result.finished_at}</span></>
            )}
          </div>
        </motion.div>
      )}
    </div>
  )
}
