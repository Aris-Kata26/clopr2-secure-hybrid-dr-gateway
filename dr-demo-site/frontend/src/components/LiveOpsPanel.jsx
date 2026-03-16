import { useState, useEffect, useContext, useCallback } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { ModeContext } from '../App.jsx'
import ConfirmModal from './ConfirmModal.jsx'
import LogStream from './LogStream.jsx'

const ACTION_GROUPS = [
  {
    id: 'prechecks',
    title: 'Pre-Checks',
    icon: '🔍',
    color: 'border-sky-800/40',
    accent: '#38bdf8',
    actions: ['precheck_onprem', 'precheck_fullsite'],
  },
  {
    id: 'onprem',
    title: 'On-Prem HA',
    icon: '🏠',
    color: 'border-violet-800/40',
    accent: '#a78bfa',
    actions: ['onprem_failover', 'onprem_fallback'],
  },
  {
    id: 'fullsite',
    title: 'Full-Site DR',
    icon: '☁',
    color: 'border-amber-800/40',
    accent: '#f59e0b',
    actions: ['fullsite_failover', 'fullsite_fallback'],
  },
  {
    id: 'utils',
    title: 'Utilities',
    icon: '📄',
    color: 'border-slate-700/40',
    accent: '#64748b',
    actions: ['export_evidence'],
  },
]

export default function LiveOpsPanel() {
  const { mode, modeInfo } = useContext(ModeContext)
  const [activeRun, setActiveRun] = useState(null)
  const [currentRunId, setCurrentRunId] = useState(null)
  const [runHistory, setRunHistory] = useState([])
  const [modal, setModal] = useState(null)  // { actionKey, isDryRun }
  const [precheckStatus, setPrecheckStatus] = useState({})  // actionKey -> 'passed'|'failed'

  const actions = modeInfo?.actions || {}

  // Poll active run every 2s when in live mode
  useEffect(() => {
    if (mode !== 'live') return
    const poll = async () => {
      try {
        const r = await fetch('/api/run/active')
        const d = await r.json()
        setActiveRun(d)
      } catch {}
    }
    poll()
    const id = setInterval(poll, 2000)
    return () => clearInterval(id)
  }, [mode])

  // Fetch run history on mount and after each run
  const fetchHistory = useCallback(async () => {
    try {
      const r = await fetch('/api/runs')
      const d = await r.json()
      setRunHistory(d.slice(0, 8))
    } catch {}
  }, [])

  useEffect(() => { fetchHistory() }, [fetchHistory])

  const isRunning = !!activeRun && activeRun.status === 'running'
  const isBusy = isRunning || !!currentRunId

  const handleActionClick = (actionKey, isDryRun) => {
    const spec = actions[actionKey]
    if (!spec) return
    // Non-destructive + no confirm needed → run directly
    if (!spec.destructive || !spec.confirm_token || isDryRun) {
      startRun(actionKey, isDryRun, false, '')
    } else {
      setModal({ actionKey, isDryRun })
    }
  }

  const startRun = async (actionKey, isDryRun, confirmed, confirmToken) => {
    try {
      const r = await fetch('/api/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: actionKey,
          dry_run: isDryRun,
          confirmed,
          confirm_token: confirmToken,
        }),
      })
      if (!r.ok) {
        const err = await r.json()
        alert(`Error: ${err.detail}`)
        return
      }
      const run = await r.json()
      setCurrentRunId(run.run_id)
    } catch (e) {
      alert(`Failed to start run: ${e.message}`)
    }
  }

  const handleConfirm = () => {
    if (!modal) return
    const { actionKey, isDryRun } = modal
    const spec = actions[actionKey]
    setModal(null)
    startRun(actionKey, isDryRun, true, spec?.confirm_token || '')
  }

  const handleRunComplete = (result) => {
    // Update precheck status
    if (modal === null && currentRunId) {
      const hist = runHistory
      if (hist.length > 0) {
        const last = hist[0]
        if (last.action.startsWith('precheck')) {
          setPrecheckStatus(prev => ({
            ...prev,
            [last.action]: result.exit_code === 0 ? 'passed' : 'failed',
          }))
        }
      }
    }
    fetchHistory()
    setTimeout(() => {
      setCurrentRunId(null)
      setActiveRun(null)
    }, 2000)
  }

  if (mode !== 'live') return null

  const prechecksPassed = Object.values(precheckStatus).length > 0 &&
    Object.values(precheckStatus).every(s => s === 'passed')

  return (
    <div>
      {/* Warning banner */}
      <div className="flex items-center gap-3 mb-6 rounded-xl border border-red-900/40 bg-red-950/20 px-5 py-3">
        <span className="text-red-400 text-lg flex-shrink-0">⚠</span>
        <div className="text-xs text-slate-300">
          <span className="font-bold text-red-400">LIVE MODE ACTIVE</span>
          {' — '}Actions marked <span className="font-bold text-red-300">DESTRUCTIVE</span> will make real infrastructure changes.
          Always run <span className="font-mono text-sky-300">Dry Run</span> first.
          Scope: <span className="font-mono text-amber-300">{modeInfo?.live_action_scope?.toUpperCase() || 'UNKNOWN'}</span>
        </div>
      </div>

      {/* Pre-check gate status */}
      <div className="flex items-center gap-3 mb-6 text-xs">
        <span className="text-slate-500 font-semibold">Pre-checks:</span>
        {Object.keys(precheckStatus).length === 0 ? (
          <span className="text-slate-500 italic">Not run yet — run pre-checks before live destructive actions</span>
        ) : prechecksPassed ? (
          <span className="text-emerald-400 font-bold flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-emerald-400" />PASS — destructive actions unlocked
          </span>
        ) : (
          <span className="text-red-400 font-bold flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-red-400" />FAIL — fix issues before proceeding
          </span>
        )}
      </div>

      {/* Action grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {ACTION_GROUPS.map(group => (
          <div key={group.id}
               className={`rounded-xl border ${group.color} p-4`}
               style={{ background: 'rgba(10,15,26,0.8)' }}>
            <div className="flex items-center gap-2 mb-3">
              <span className="text-base">{group.icon}</span>
              <span className="text-xs font-bold text-slate-200 tracking-wide">{group.title}</span>
            </div>
            <div className="space-y-2">
              {group.actions.map(key => {
                const spec = actions[key]
                if (!spec) return null
                const enabled = spec.enabled
                const needsPrecheck = spec.destructive && !prechecksPassed && key !== 'export_evidence'

                return (
                  <ActionButton
                    key={key}
                    actionKey={key}
                    spec={spec}
                    enabled={enabled && !isBusy}
                    needsPrecheck={needsPrecheck}
                    accent={group.accent}
                    onAction={handleActionClick}
                  />
                )
              })}
            </div>
          </div>
        ))}
      </div>

      {/* Log stream */}
      <AnimatePresence>
        {currentRunId && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="mb-6"
          >
            <div className="flex items-center justify-between mb-2">
              <p className="text-xs font-bold text-slate-300 uppercase tracking-wide">Live Log Stream</p>
              {activeRun && (
                <span className="text-xs text-slate-500 font-mono">
                  {activeRun.action} {activeRun.dry_run ? '(dry-run)' : '(live)'}
                </span>
              )}
            </div>
            <LogStream runId={currentRunId} onComplete={handleRunComplete} />
          </motion.div>
        )}
      </AnimatePresence>

      {/* Run history */}
      {runHistory.length > 0 && (
        <div className="rounded-xl border border-white/8 overflow-hidden"
             style={{ background: 'rgba(17,24,39,0.5)' }}>
          <div className="px-4 py-2.5 border-b border-white/5">
            <span className="text-xs font-bold text-slate-400 uppercase tracking-wide">Recent Runs</span>
          </div>
          <div className="divide-y divide-white/5">
            {runHistory.map((run, i) => (
              <div key={run.run_id} className="flex items-center gap-3 px-4 py-2.5 text-xs">
                <span className={`font-bold w-12 ${
                  run.status === 'passed' ? 'text-emerald-400' :
                  run.status === 'failed' ? 'text-red-400' :
                  'text-amber-400'
                }`}>
                  {run.status?.toUpperCase()}
                </span>
                <span className="text-slate-300 font-medium">{run.label || run.action}</span>
                {run.dry_run && (
                  <span className="text-amber-500 font-mono text-xs">dry-run</span>
                )}
                <span className="ml-auto text-slate-600 font-mono">
                  {run.started_at ? new Date(run.started_at).toLocaleTimeString() : ''}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Confirm modal */}
      <AnimatePresence>
        {modal && (
          <ConfirmModal
            action={actions[modal.actionKey]}
            actionKey={modal.actionKey}
            onConfirm={handleConfirm}
            onCancel={() => setModal(null)}
          />
        )}
      </AnimatePresence>
    </div>
  )
}

function ActionButton({ actionKey, spec, enabled, needsPrecheck, accent, onAction }) {
  const showDryRun = spec.dry_run_supported && spec.destructive
  const disabled = !enabled

  const btnBase = `w-full text-left px-3 py-2 rounded-lg text-xs font-semibold transition-all border`

  if (showDryRun) {
    return (
      <div className="space-y-1">
        <div className="text-xs text-slate-500 font-medium mb-0.5">{spec.label}</div>
        <div className="flex gap-1.5">
          <button
            onClick={() => !disabled && onAction(actionKey, true)}
            disabled={disabled}
            title="Dry run — no changes"
            className={`flex-1 ${btnBase} border-amber-800/40 text-amber-300 hover:bg-amber-950/30 ${disabled ? 'opacity-40 cursor-not-allowed' : ''}`}
          >
            Dry Run
          </button>
          <button
            onClick={() => !disabled && !needsPrecheck && onAction(actionKey, false)}
            disabled={disabled || needsPrecheck}
            title={needsPrecheck ? 'Run pre-checks first' : 'Execute live — real changes'}
            className={`flex-1 ${btnBase} border-red-800/50 text-red-300 hover:bg-red-950/30 ${
              (disabled || needsPrecheck) ? 'opacity-40 cursor-not-allowed' : ''
            }`}
          >
            Live ▶
          </button>
        </div>
      </div>
    )
  }

  return (
    <div>
      <button
        onClick={() => !disabled && onAction(actionKey, false)}
        disabled={disabled}
        className={`${btnBase} border-sky-800/40 text-sky-300 hover:bg-sky-950/30 ${disabled ? 'opacity-40 cursor-not-allowed' : ''}`}
      >
        {spec.label} ▶
      </button>
    </div>
  )
}
