import { useState, useEffect, useCallback } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

const PHASE_LABELS = {
  'on-prem-ha':   { label: 'On-Prem HA (S4-03)', color: 'text-sky-400',   bg: 'bg-sky-950/40 border-sky-800/40' },
  'full-site-dr': { label: 'Full-Site DR (S5-01)', color: 'text-amber-400', bg: 'bg-amber-950/40 border-amber-800/40' },
}

function hlLine(line) {
  return line
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"([\w_]+)":/g, '<span style="color:#7dd3fc">"$1":</span>')
    .replace(/\btrue\b/g,    '<span style="color:#4ade80;font-weight:700">true</span>')
    .replace(/\bfalse\b/g,   '<span style="color:#f87171;font-weight:700">false</span>')
    .replace(/\b(PASS|COMPLETE|HEALTHY|MASTER|streaming)\b/g,'<span style="color:#4ade80;font-weight:700">$1</span>')
    .replace(/\b(FAIL|STOPPED|inactive|dead)\b/g,            '<span style="color:#f87171;font-weight:700">$1</span>')
    .replace(/(\d{4}-\d{2}-\d{2}T[\d:Z.]+)/g,               '<span style="color:#94a3b8">$1</span>')
    .replace(/(0\/[0-9A-F]+)/g,                              '<span style="color:#fbbf24">$1</span>')
}

const PROOF = [
  {
    title: 'Pre-test baseline',    tag: 'NORMAL',    tagColor: 'text-emerald-400 bg-emerald-950/60 border-emerald-800/40',
    json: { status:'ok', db:'ok', db_host:'10.0.96.10', pg_is_in_recovery: false, app_env:'dev', ts:'2026-03-14T14:29:18Z' },
    note: 'On-prem primary active, app healthy',
  },
  {
    title: 'On-prem failover — standby serving', tag: 'DEGRADED', tagColor: 'text-amber-400 bg-amber-950/60 border-amber-800/40',
    json: { status:'ok', db:'ok', db_host:'10.0.96.10', pg_is_in_recovery: true, app_env:'dev', ts:'2026-03-14T15:49:13Z' },
    note: 'VIP on pg-standby · reads served',
  },
  {
    title: 'On-prem fallback restored', tag: 'RESTORED', tagColor: 'text-emerald-400 bg-emerald-950/60 border-emerald-800/40',
    json: { status:'ok', db:'ok', db_host:'10.0.96.10', pg_is_in_recovery: false, app_env:'dev', ts:'2026-03-14T15:52:38Z' },
    note: 'VIP back on pg-primary',
  },
  {
    title: 'Azure DR VM promoted', tag: 'DR ACTIVE', tagColor: 'text-amber-400 bg-amber-950/60 border-amber-800/40',
    json: { status:'ok', db:'ok', db_host:'127.0.0.1', pg_is_in_recovery: false, app_env:'dr-azure', ts:'2026-03-16T14:41:53Z' },
    note: 'S5-01 automated · Azure primary · RTO 32s',
  },
  {
    title: 'Full-site failback complete', tag: 'RESTORED', tagColor: 'text-emerald-400 bg-emerald-950/60 border-emerald-800/40',
    json: { status:'ok', db:'ok', db_host:'10.0.96.10', pg_is_in_recovery: false, app_env:'dev', ts:'2026-03-16T14:49:38Z' },
    note: 'S5-01 automated · On-prem restored · App RTO 103s',
  },
]

export default function EvidenceViewer() {
  const [files, setFiles]       = useState([])
  const [filter, setFilter]     = useState('all')
  const [selected, setSelected] = useState(null)
  const [content, setContent]   = useState(null)
  const [loading, setLoading]   = useState(false)
  const [copied, setCopied]     = useState(false)
  const [search, setSearch]     = useState('')

  const fetchFiles = useCallback(() => {
    fetch('/api/evidence').then(r => r.json()).then(setFiles).catch(() => {})
  }, [])

  useEffect(() => {
    fetchFiles()
    // Refresh file list every 10s to catch new evidence from live runs
    const id = setInterval(fetchFiles, 10000)
    return () => clearInterval(id)
  }, [fetchFiles])

  const filtered = files.filter(f => {
    const phaseMatch = filter === 'all' || f.phase === filter
    const searchMatch = !search || f.name.toLowerCase().includes(search.toLowerCase())
    return phaseMatch && searchMatch
  })

  const openFile = async (f) => {
    if (selected?.name === f.name) { setSelected(null); setContent(null); return }
    setSelected(f)
    setLoading(true)
    setContent(null)
    try {
      const r = await fetch(`/api/evidence/${f.name}`)
      const d = await r.json()
      setContent(d.content)
    } catch { setContent('Could not load file.') }
    setLoading(false)
  }

  const copyContent = async () => {
    if (!content) return
    await navigator.clipboard.writeText(content).catch(() => {})
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <div>
      {/* /health proof cards */}
      <p className="text-sm text-slate-400 mb-4">
        Actual <span className="font-mono text-sky-400">/health</span> responses at key phases:
      </p>
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-3 mb-10">
        {PROOF.map((p, i) => (
          <motion.div
            key={p.title}
            className="rounded-xl border border-white/8 overflow-hidden"
            style={{ background: 'rgba(10,15,26,0.95)' }}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: i * 0.07 }}
          >
            <div className="flex items-center justify-between px-4 py-2 border-b border-white/5"
                 style={{ background: 'rgba(30,41,59,0.5)' }}>
              <span className="text-xs font-semibold text-slate-300">{p.title}</span>
              <span className={`text-xs font-bold px-2 py-0.5 rounded-md border ${p.tagColor}`}>{p.tag}</span>
            </div>
            <div className="p-3">
              <pre className="evidence-code text-xs leading-relaxed">
                {JSON.stringify(p.json, null, 2).split('\n').map((line, j) => (
                  <span key={j} dangerouslySetInnerHTML={{ __html: hlLine(line) + '\n' }} />
                ))}
              </pre>
              <p className="text-xs text-slate-500 mt-2 border-t border-white/5 pt-2">{p.note}</p>
            </div>
          </motion.div>
        ))}
      </div>

      {/* Evidence file browser */}
      <div className="border border-white/8 rounded-2xl overflow-hidden"
           style={{ background: 'rgba(17,24,39,0.8)' }}>
        <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-3 border-b border-white/5">
          <div className="flex items-center gap-3">
            <span className="text-sm font-semibold text-white">Evidence file browser</span>
            <span className="text-xs text-slate-500">{filtered.length} files</span>
            {files.some(f => f.is_new) && (
              <span className="text-xs font-bold text-emerald-400 bg-emerald-950/60 border border-emerald-800/40 px-2 py-0.5 rounded animate-pulse">
                NEW files
              </span>
            )}
          </div>
          <div className="flex gap-2 flex-wrap">
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Filter…"
              className="text-xs px-2.5 py-1 rounded-lg border border-white/10 bg-black/30 text-slate-300 outline-none w-28"
            />
            {['all','on-prem-ha','full-site-dr'].map(f => (
              <button key={f} onClick={() => setFilter(f)}
                className={`text-xs px-3 py-1 rounded-lg border transition-colors ${
                  filter === f
                    ? 'bg-sky-950/60 border-sky-700 text-sky-300'
                    : 'border-white/8 text-slate-400 hover:border-white/20'
                }`}>
                {f === 'all' ? 'All' : PHASE_LABELS[f]?.label || f}
              </button>
            ))}
          </div>
        </div>

        <div className="flex" style={{ height: '360px' }}>
          {/* File list */}
          <div className="w-72 border-r border-white/5 overflow-y-auto flex-shrink-0">
            {filtered.map(f => (
              <button key={f.name} onClick={() => openFile(f)}
                className={`w-full text-left px-3 py-2 border-b border-white/3 transition-colors flex items-center gap-2 ${
                  selected?.name === f.name
                    ? 'bg-sky-950/40 text-sky-300'
                    : 'text-slate-400 hover:bg-white/3 hover:text-slate-200'
                }`}>
                <span className={`text-xs px-1.5 py-0.5 rounded flex-shrink-0 ${
                  PHASE_LABELS[f.phase]?.bg || 'bg-slate-800'
                } ${PHASE_LABELS[f.phase]?.color || 'text-slate-400'}`}>
                  {f.phase === 'on-prem-ha' ? 'HA' : 'DR'}
                </span>
                <span className="font-mono text-xs truncate flex-1">{f.name}</span>
                {f.is_new && (
                  <span className="text-xs font-bold text-emerald-400 flex-shrink-0">NEW</span>
                )}
              </button>
            ))}
            {filtered.length === 0 && (
              <div className="px-4 py-6 text-xs text-slate-600 text-center">No files match filter</div>
            )}
          </div>

          {/* Content panel */}
          <div className="flex-1 overflow-y-auto p-4 relative">
            <AnimatePresence mode="wait">
              {selected ? (
                <motion.div key={selected.name} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.2 }}>
                  <div className="flex items-center gap-3 mb-3">
                    <p className="font-mono text-xs text-sky-400 font-bold flex-1">{selected.name}</p>
                    <button onClick={copyContent}
                      className="text-xs px-2.5 py-1 rounded border border-white/10 text-slate-400 hover:border-white/20 hover:text-slate-200 transition-colors">
                      {copied ? '✓ Copied' : 'Copy'}
                    </button>
                  </div>
                  {loading ? (
                    <div className="text-slate-500 text-xs animate-pulse">Loading…</div>
                  ) : (
                    <pre className="evidence-code text-xs text-slate-300 leading-relaxed">
                      {(content || '').split('\n').map((line, i) => (
                        <span key={i} dangerouslySetInnerHTML={{ __html: hlLine(line) + '\n' }} />
                      ))}
                    </pre>
                  )}
                </motion.div>
              ) : (
                <div className="flex items-center justify-center h-full text-slate-600 text-sm">
                  ← Select a file to view
                </div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </div>
    </div>
  )
}
