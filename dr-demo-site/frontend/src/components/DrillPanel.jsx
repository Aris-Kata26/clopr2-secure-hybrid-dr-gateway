import { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

const DRILL_IDS = [
  { id: 'onprem-failover',  label: 'On-Prem Failover',   date: '2026-03-14', sprint: 'S4-03' },
  { id: 'onprem-fallback',  label: 'On-Prem Fallback',   date: '2026-03-14', sprint: 'S4-03' },
  { id: 'fullsite-failover',label: 'Full-Site → Azure',  date: '2026-03-15', sprint: 'S4-09' },
  { id: 'fullsite-failback',label: 'Full-Site → On-Prem',date: '2026-03-15', sprint: 'S4-09' },
]

export default function DrillPanel({ activeDrill, onDrillChange }) {
  const [drill, setDrill]       = useState(null)
  const [activeStep, setActiveStep] = useState(null)
  const [stepContent, setStepContent] = useState(null)
  const [loadingStep, setLoadingStep] = useState(false)

  useEffect(() => {
    setDrill(null)
    setActiveStep(null)
    setStepContent(null)
    fetch(`/api/drills/${activeDrill}`)
      .then(r => r.json())
      .then(setDrill)
      .catch(() => {})
  }, [activeDrill])

  const loadStep = async (step) => {
    if (activeStep?.id === step.id) {
      setActiveStep(null)
      setStepContent(null)
      return
    }
    setActiveStep(step)
    setLoadingStep(true)
    setStepContent(null)
    try {
      const r = await fetch(`/api/evidence/${step.file}`)
      const d = await r.json()
      setStepContent(d.content)
    } catch {
      setStepContent('Evidence file not available.')
    }
    setLoadingStep(false)
  }

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
                ? 'bg-sky-950/60 border-sky-600 text-sky-300'
                : 'border-white/8 text-slate-400 hover:border-white/20 hover:text-slate-200'
            }`}
            style={{ minWidth: '160px' }}
          >
            <span className="text-xs font-bold mb-0.5">{d.label}</span>
            <span className="text-xs opacity-60">{d.sprint} · {d.date}</span>
          </button>
        ))}
      </div>

      {/* Drill content */}
      <AnimatePresence mode="wait">
        {drill ? (
          <motion.div
            key={activeDrill}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: .25 }}
          >
            {/* Header */}
            <div className="flex flex-wrap items-start justify-between gap-4 mb-6">
              <div>
                <h3 className="text-xl font-bold text-white mb-1">{drill.name}</h3>
                <p className="text-sm text-slate-400 max-w-2xl">{drill.summary}</p>
              </div>
              <div className="flex gap-3 flex-shrink-0">
                <Metric label="RTO" value={drill.rto} color="text-emerald-400" />
                <Metric label="RPO" value={drill.rpo} color="text-sky-400" />
                <Metric label="Verdict" value={drill.verdict} color="text-emerald-400" />
              </div>
            </div>

            {/* Steps */}
            <div className="space-y-1.5">
              {drill.steps.map((step, i) => (
                <StepRow
                  key={step.id}
                  step={step}
                  index={i}
                  isOpen={activeStep?.id === step.id}
                  loading={loadingStep && activeStep?.id === step.id}
                  content={activeStep?.id === step.id ? stepContent : null}
                  onClick={() => loadStep(step)}
                />
              ))}
            </div>

            <div className="mt-4 flex items-center gap-2">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
              <span className="text-xs text-slate-500">
                Click any step to view evidence file content
              </span>
            </div>
          </motion.div>
        ) : (
          <div className="flex items-center justify-center h-40 text-slate-500 text-sm">
            Loading drill data…
          </div>
        )}
      </AnimatePresence>
    </div>
  )
}

function StepRow({ step, index, isOpen, loading, content, onClick }) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -8 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: .2, delay: index * .03 }}
    >
      <button
        onClick={onClick}
        className={`w-full text-left rounded-lg border px-4 py-3 transition-all duration-200
          flex items-start gap-3 ${
          isOpen
            ? 'border-sky-700/50 bg-sky-950/30'
            : 'border-white/5 hover:border-white/15 hover:bg-white/2'
        }`}
      >
        {/* Step badge */}
        <span className="flex-shrink-0 text-xs font-bold font-mono px-1.5 py-0.5 rounded"
              style={{ background: 'rgba(34,197,94,0.12)', color: '#22c55e' }}>
          {step.id}
        </span>

        {/* Check icon */}
        <span className="flex-shrink-0 mt-0.5 text-emerald-400">✔</span>

        {/* Name + detail */}
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-slate-200">{step.name}</p>
          <p className="text-xs text-slate-500 mt-0.5">{step.detail}</p>
        </div>

        {/* File ref + expand */}
        <div className="flex items-center gap-3 flex-shrink-0">
          <span className="text-xs font-mono text-slate-500 hidden sm:block">{step.file}</span>
          <span className="text-slate-500 text-sm">{isOpen ? '▲' : '▼'}</span>
        </div>
      </button>

      {/* Expanded evidence */}
      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: .25 }}
            className="overflow-hidden"
          >
            <div className="mx-2 mb-2 rounded-b-lg border border-t-0 border-sky-700/30"
                 style={{ background: 'rgba(5,15,30,0.9)' }}>
              <div className="flex items-center gap-2 px-4 py-2 border-b border-white/5">
                <span className="w-2 h-2 rounded-full bg-sky-400" />
                <span className="text-xs text-sky-400 font-mono font-semibold">{step.file}</span>
                <span className="ml-auto text-xs text-slate-600">evidence · read-only</span>
              </div>
              <div className="p-4 max-h-64 overflow-y-auto">
                {loading ? (
                  <div className="text-slate-500 text-xs animate-pulse">Loading evidence…</div>
                ) : (
                  <pre className="evidence-code text-slate-300 text-xs leading-relaxed whitespace-pre-wrap">
                    <EvidenceHighlight content={content || ''} />
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

function EvidenceHighlight({ content }) {
  // Colourize JSON strings, true/false, timestamps, PASS/FAIL
  return content
    .split('\n')
    .map((line, i) => {
      let colored = line
        .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')

      colored = colored
        .replace(/"([\w_]+)":/g, '<span style="color:#7dd3fc">"$1":</span>')
        .replace(/\btrue\b/g,    '<span style="color:#4ade80;font-weight:700">true</span>')
        .replace(/\bfalse\b/g,   '<span style="color:#f87171;font-weight:700">false</span>')
        .replace(/\b(PASS|COMPLETE)\b/g,'<span style="color:#4ade80;font-weight:700">$1</span>')
        .replace(/\b(FAIL)\b/g,         '<span style="color:#f87171;font-weight:700">$1</span>')
        .replace(/(\d{4}-\d{2}-\d{2}T[\d:Z.]+)/g,'<span style="color:#94a3b8">$1</span>')

      return (
        <span key={i} dangerouslySetInnerHTML={{ __html: colored + '\n' }} />
      )
    })
}

function Metric({ label, value, color }) {
  return (
    <div className="rounded-lg border border-white/8 px-4 py-2 text-center min-w-[80px]"
         style={{ background: 'rgba(17,24,39,0.8)' }}>
      <p className={`text-sm font-bold ${color}`}>{value}</p>
      <p className="text-xs text-slate-500 mt-0.5">{label}</p>
    </div>
  )
}
