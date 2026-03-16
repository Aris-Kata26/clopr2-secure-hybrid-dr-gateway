import { useContext } from 'react'
import { ModeContext } from '../App.jsx'

export default function ModeToggle() {
  const { mode, setMode, modeInfo } = useContext(ModeContext)
  const liveAvailable = modeInfo?.live_enabled === true

  return (
    <div className="flex items-center gap-2">
      {mode === 'live' && (
        <span className="flex items-center gap-1.5 text-xs font-bold text-red-400 bg-red-950/60 border border-red-800/60 px-2 py-0.5 rounded-full animate-pulse">
          <span className="w-1.5 h-1.5 rounded-full bg-red-400 inline-block" />
          REAL INFRA
        </span>
      )}
      <div className="flex rounded-lg border border-white/10 overflow-hidden text-xs font-bold">
        <button
          onClick={() => setMode('demo')}
          className={`px-3 py-1.5 transition-colors ${
            mode === 'demo'
              ? 'bg-sky-600 text-white'
              : 'bg-transparent text-slate-400 hover:text-slate-200'
          }`}
        >
          DEMO
        </button>
        <button
          onClick={() => liveAvailable && setMode('live')}
          title={!liveAvailable ? 'Live mode not available (LIVE_MODE_ENABLED=false)' : undefined}
          className={`px-3 py-1.5 transition-colors border-l border-white/10 ${
            mode === 'live'
              ? 'bg-red-700 text-white'
              : liveAvailable
                ? 'bg-transparent text-slate-400 hover:text-red-300'
                : 'bg-transparent text-slate-600 cursor-not-allowed'
          }`}
        >
          LIVE
          {!liveAvailable && <span className="ml-1 text-slate-600">⊘</span>}
        </button>
      </div>
    </div>
  )
}
