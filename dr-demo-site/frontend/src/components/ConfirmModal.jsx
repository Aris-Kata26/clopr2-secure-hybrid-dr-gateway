import { useState, useEffect, useRef } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

export default function ConfirmModal({ action, actionKey, onConfirm, onCancel }) {
  const [token1, setToken1] = useState('')
  const [token2, setToken2] = useState('')
  const [checked, setChecked] = useState(false)
  const [shake, setShake] = useState(false)
  const inputRef = useRef(null)

  useEffect(() => {
    setTimeout(() => inputRef.current?.focus(), 100)
  }, [])

  if (!action) return null

  const isTwoGate = action.two_gate === true
  const expectedToken = action.confirm_token || ''
  const token1Match = token1 === expectedToken
  const token2Match = !isTwoGate || token2 === expectedToken
  const canSubmit = (!action.destructive || (token1Match && token2Match)) && checked

  const handleSubmit = () => {
    if (!canSubmit) {
      setShake(true)
      setTimeout(() => setShake(false), 500)
      return
    }
    onConfirm()
  }

  const riskColor = action.destructive
    ? 'text-red-400 bg-red-950/60 border-red-700'
    : 'text-amber-400 bg-amber-950/60 border-amber-700'

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
         style={{ background: 'rgba(0,0,0,0.85)' }}
         onClick={(e) => e.target === e.currentTarget && onCancel()}>
      <motion.div
        initial={{ scale: 0.95, opacity: 0 }}
        animate={shake ? { x: [0, -8, 8, -8, 8, 0] } : { scale: 1, opacity: 1 }}
        exit={{ scale: 0.95, opacity: 0 }}
        transition={{ duration: shake ? 0.4 : 0.2 }}
        className="w-full max-w-lg rounded-2xl border border-white/10 shadow-2xl"
        style={{ background: '#0f172a' }}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-white/8">
          <div className="flex items-center gap-3">
            <span className="text-lg">{action.destructive ? '⚠' : '▶'}</span>
            <div>
              <p className="font-bold text-white text-sm">{action.label}</p>
              <p className="text-xs text-slate-400 mt-0.5">{actionKey}</p>
            </div>
          </div>
          <span className={`text-xs font-bold px-2 py-1 rounded border ${riskColor}`}>
            {action.destructive ? 'DESTRUCTIVE' : 'READ-ONLY'}
          </span>
        </div>

        {/* Body */}
        <div className="px-6 py-5 space-y-4">
          <p className="text-sm text-slate-300 leading-relaxed">{action.description}</p>

          {action.destructive && (
            <div className="rounded-xl border border-red-900/40 bg-red-950/20 p-4">
              <p className="text-xs font-bold text-red-400 uppercase tracking-wide mb-2">
                This will make real infrastructure changes
              </p>
              <ul className="text-xs text-slate-400 space-y-1 list-disc list-inside">
                <li>Changes cannot be automatically undone</li>
                <li>Ensure pre-checks have passed first</li>
                {isTwoGate && <li>This action requires two confirmation gates</li>}
              </ul>
            </div>
          )}

          {/* Gate 1 confirmation */}
          {action.destructive && (
            <div>
              <label className="block text-xs font-semibold text-slate-400 mb-1.5">
                {isTwoGate ? 'GATE 1 — ' : ''}Type <span className="text-red-400 font-mono">{expectedToken}</span> to confirm:
              </label>
              <input
                ref={inputRef}
                value={token1}
                onChange={e => setToken1(e.target.value.toUpperCase())}
                onKeyDown={e => e.key === 'Enter' && handleSubmit()}
                placeholder={expectedToken}
                className={`w-full px-3 py-2 rounded-lg border font-mono text-sm bg-black/40 outline-none transition-colors ${
                  token1 === '' ? 'border-white/10 text-slate-300' :
                  token1Match ? 'border-emerald-600 text-emerald-300' :
                  'border-red-700 text-red-300'
                }`}
              />
            </div>
          )}

          {/* Gate 2 confirmation (fullsite_fallback only) */}
          {action.destructive && isTwoGate && (
            <div>
              <label className="block text-xs font-semibold text-slate-400 mb-1.5">
                GATE 2 — Type <span className="text-red-400 font-mono">{expectedToken}</span> again to confirm DR-VM rebuild:
              </label>
              <input
                value={token2}
                onChange={e => setToken2(e.target.value.toUpperCase())}
                onKeyDown={e => e.key === 'Enter' && handleSubmit()}
                placeholder={expectedToken}
                className={`w-full px-3 py-2 rounded-lg border font-mono text-sm bg-black/40 outline-none transition-colors ${
                  token2 === '' ? 'border-white/10 text-slate-300' :
                  token2Match ? 'border-emerald-600 text-emerald-300' :
                  'border-red-700 text-red-300'
                }`}
              />
            </div>
          )}

          {/* Acknowledgement checkbox */}
          <label className="flex items-start gap-3 cursor-pointer select-none group">
            <div className={`mt-0.5 w-4 h-4 rounded border flex-shrink-0 flex items-center justify-center transition-colors ${
              checked ? 'bg-sky-500 border-sky-500' : 'border-white/20 group-hover:border-white/40'
            }`}
              onClick={() => setChecked(c => !c)}>
              {checked && <span className="text-white text-xs font-bold">✓</span>}
            </div>
            <span className="text-xs text-slate-400 leading-snug">
              I understand this action will{' '}
              {action.destructive ? (
                <span className="text-red-400 font-semibold">execute real infrastructure changes</span>
              ) : (
                <span className="text-sky-400 font-semibold">run a read-only script</span>
              )}
              {' '}on the connected hosts.
            </span>
          </label>
        </div>

        {/* Footer */}
        <div className="flex gap-3 px-6 py-4 border-t border-white/8">
          <button
            onClick={onCancel}
            className="flex-1 px-4 py-2 rounded-lg border border-white/10 text-slate-400 text-sm
                       hover:border-white/20 hover:text-slate-200 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={!canSubmit}
            className={`flex-1 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${
              canSubmit
                ? action.destructive
                  ? 'bg-red-700 hover:bg-red-600 text-white'
                  : 'bg-sky-600 hover:bg-sky-500 text-white'
                : 'bg-slate-800 text-slate-500 cursor-not-allowed'
            }`}
          >
            {action.destructive ? '⚠ Execute Live' : '▶ Run'}
          </button>
        </div>
      </motion.div>
    </div>
  )
}
