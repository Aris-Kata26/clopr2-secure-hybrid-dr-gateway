import { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

const DRILL_IDS = [
  { id: 'onprem-failover',  label: 'On-Prem Failover',    date: '2026-03-14', sprint: 'S4-03', color: 'border-emerald-700 text-emerald-300', active: 'bg-emerald-950/40 border-emerald-600' },
  { id: 'onprem-fallback',  label: 'On-Prem Fallback',    date: '2026-03-14', sprint: 'S4-03', color: 'border-sky-700 text-sky-300',         active: 'bg-sky-950/40 border-sky-600' },
  { id: 'fullsite-failover',label: 'Full-Site → Azure',   date: '2026-03-16', sprint: 'S5-01', color: 'border-amber-700 text-amber-300',     active: 'bg-amber-950/40 border-amber-600' },
  { id: 'fullsite-failback',label: 'Full-Site → On-Prem', date: '2026-03-16', sprint: 'S5-01', color: 'border-violet-700 text-violet-300',   active: 'bg-violet-950/40 border-violet-600' },
]

export default function DrillPanel({ activeDrill, onDrillChange }) {
  const [drill, setDrill]         = useState(null)
  const [activeStep, setActiveStep] = useState(null)
  const [stepContent, setStepContent] = useState(null)
  const [loadingStep, setLoadingStep] = useState(false)
  const [copied, setCopied]       = useState(false)

  useEffect(() => {
    setDrill(null)
    setActiveStep(null)
    setStepContent(null)
    fetch(`/api/drills/${activeDrill}`)
      .then(r => r.json()).then(setDrill).catch(() => {})
  }, [activeDrill])

  const loadStep = async (step) => {
    if (activeStep?.id === step.id) { setActiveStep(null); setStepContent(null); return }
    setActiveStep(step)
    setLoadingStep(true)
    setStepContent(null)
    try {
      const r = await fetch(`/api/evidence/${step.file}`)
      const d = await r.json()
      setStepContent(d.content)
    } catch { setStepContent('Evidence file not available.') }
    setLoadingStep(false)
  }

  const copyContent = async () => {
    if (!stepContent) return
    await navigator.clipboard.writeText(stepContent).catch(() => {})
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  const meta = DRILL_IDS.find(d => d.id === activeDrill)

  return (
    <div>
      {/* Tab row */}
      <div className="flex flex-wrap gap-2 mb-6">
        {DRILL_IDS.map(d => (
          <button
            key={d.id}
            onClick={() => onDrillChange(d.id)}
            className={`flex flex-col items-start px-4 py-2.5 rounded-xl border text-left
              transition-all duration-200 ${
              activeDrill === d.id
                ? d.active
                : `border-white/8 text-slate-400 hover:border-white/20 hover:text-slate-200`
            }`}
            style={{ minWidth: '160px' }}
          >
            <span className={`text-xs font-bold mb-0.5 ${activeDrill === d.id ? '' : 'text-slate-300'}`}>
              {d.label}
            </span>
            <span className="text-xs opacity-60">{d.sprint} · {d.date}</span>
          </button>
        ))}
      </div>

      <AnimatePresence mode="wait">
        {drill ? (
          <motion.div
            key={activeDrill}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.25 }}
          >
            {/* Header with verdict */}
            <div className="flex flex-wrap items-start justify-between gap-4 mb-6">
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-1">
                  <h3 className="text-xl font-bold text-white">{drill.name}</h3>
                  <VerdictBadge verdict={drill.verdict} />
                </div>
                <p className="text-sm text-slate-400 max-w-2xl">{drill.summary}</p>
              </div>
              <div className="flex gap-2 flex-shrink-0 flex-wrap">
                <Metric label="RTO" value={drill.rto} color="text-emerald-400" />
                <Metric label="RPO" value={drill.rpo} color="text-sky-400" />
              </div>
            </div>

            {/* Timeline steps */}
            <div className="relative">
              {/* Vertical timeline line */}
              <div className="absolute left-5 top-6 bottom-6 w-px bg-white/5" />

              <div className="space-y-2">
                {drill.steps.map((step, i) => (
                  <TimelineStep
                    key={step.id}
                    step={step}
                    index={i}
                    total={drill.steps.length}
                    isOpen={activeStep?.id === step.id}
                    loading={loadingStep && activeStep?.id === step.id}
                    content={activeStep?.id === step.id ? stepContent : null}
                    copied={copied && activeStep?.id === step.id}
                    onClick={() => loadStep(step)}
                    onCopy={copyContent}
                  />
                ))}
              </div>
            </div>

            <div className="mt-4 flex items-center gap-2">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
              <span className="text-xs text-slate-500">
                Click any step to view evidence · {drill.steps.length} steps · {drill.steps.filter(s => s.status === 'PASS').length} passed
              </span>
            </div>
          </motion.div>
        ) : (
          <div className="flex items-center justify-center h-40 text-slate-500 text-sm animate-pulse">
            Loading drill…
          </div>
        )}
      </AnimatePresence>
    </div>
  )
}

function VerdictBadge({ verdict }) {
  if (verdict === 'PASS') {
    return (
      <span className="flex items-center gap-1.5 text-xs font-bold text-emerald-400 bg-emerald-950/60 border border-emerald-800 px-2.5 py-1 rounded-full">
        ✓ ALL PASS
      </span>
    )
  }
  return (
    <span className="flex items-center gap-1.5 text-xs font-bold text-red-400 bg-red-950/60 border border-red-800 px-2.5 py-1 rounded-full">
      ✗ FAILED
    </span>
  )
}

function TimelineStep({ step, index, total, isOpen, loading, content, copied, onClick, onCopy }) {
  const isLast = index === total - 1

  return (
    <motion.div
      className="relative pl-12"
      initial={{ opacity: 0, x: -12 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.2, delay: index * 0.04 }}
    >
      {/* Timeline dot */}
      <div className={`absolute left-3.5 top-3.5 w-3 h-3 rounded-full border-2 z-10 transition-colors ${
        isOpen
          ? 'bg-sky-400 border-sky-400'
          : 'bg-emerald-500 border-emerald-400'
      }`} />

      <button
        onClick={onClick}
        className={`w-full text-left rounded-xl border px-4 py-3 transition-all duration-200 flex items-start gap-3 ${
          isOpen
            ? 'border-sky-700/50 bg-sky-950/20'
            : 'border-white/5 hover:border-white/12 hover:bg-white/2'
        }`}
      >
        <span className="flex-shrink-0 text-xs font-bold font-mono px-1.5 py-0.5 rounded mt-0.5"
              style={{ background: 'rgba(34,197,94,0.12)', color: '#22c55e', minWidth: '36px', textAlign: 'center' }}>
          {step.id}
        </span>

        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-slate-200">{step.name}</p>
          <p className="text-xs text-slate-500 mt-0.5">{step.detail}</p>
        </div>

        <div className="flex items-center gap-3 flex-shrink-0">
          <span className="hidden sm:block text-xs font-mono text-slate-600">{step.file}</span>
          <span className={`text-sm transition-transform duration-200 ${isOpen ? 'rotate-180' : ''} text-slate-500`}>
            ▼
          </span>
        </div>
      </button>

      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.25 }}
            className="overflow-hidden"
          >
            <div className="ml-1 mb-2 rounded-b-xl border border-t-0 border-sky-700/30"
                 style={{ background: 'rgba(3,10,22,0.95)' }}>
              <div className="flex items-center gap-2 px-4 py-2 border-b border-white/5">
                <span className="w-2 h-2 rounded-full bg-sky-400" />
                <span className="text-xs text-sky-400 font-mono font-semibold flex-1">{step.file}</span>
                <button
                  onClick={(e) => { e.stopPropagation(); onCopy() }}
                  className="text-xs px-2.5 py-1 rounded border border-white/10 text-slate-400
                             hover:border-white/20 hover:text-slate-200 transition-colors"
                >
                  {copied ? '✓ Copied' : 'Copy'}
                </button>
              </div>
              <div className="p-4 max-h-72 overflow-y-auto">
                {loading ? (
                  <div className="text-slate-500 text-xs animate-pulse">Loading evidence…</div>
                ) : (
                  <pre className="evidence-code text-slate-300 text-xs leading-relaxed whitespace-pre-wrap">
                    {(content || '').split('\n').map((line, i) => (
                      <span key={i} dangerouslySetInnerHTML={{ __html: hlLine(line) + '\n' }} />
                    ))}
                  </pre>
                )}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  )
}

function hlLine(line) {
  return line
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"([\w_]+)":/g, '<span style="color:#7dd3fc">"$1":</span>')
    .replace(/\btrue\b/g,    '<span style="color:#4ade80;font-weight:700">true</span>')
    .replace(/\bfalse\b/g,   '<span style="color:#f87171;font-weight:700">false</span>')
    .replace(/\b(PASS|COMPLETE)\b/g, '<span style="color:#4ade80;font-weight:700">$1</span>')
    .replace(/\b(FAIL)\b/g,          '<span style="color:#f87171;font-weight:700">$1</span>')
    .replace(/(\d{4}-\d{2}-\d{2}T[\d:Z.]+)/g, '<span style="color:#94a3b8">$1</span>')
    .replace(/(0\/[0-9A-F]+)/g, '<span style="color:#fbbf24">$1</span>')
}

function Metric({ label, value, color }) {
  return (
    <div className="rounded-lg border border-white/8 px-4 py-2 text-center min-w-[100px]"
         style={{ background: 'rgba(17,24,39,0.8)' }}>
      <p className={`text-sm font-bold ${color}`}>{value}</p>
      <p className="text-xs text-slate-500 mt-0.5">{label}</p>
    </div>
  )
}
