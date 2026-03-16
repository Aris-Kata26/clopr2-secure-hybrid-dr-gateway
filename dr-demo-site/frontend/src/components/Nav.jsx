import { useContext } from 'react'
import { ModeContext } from '../App.jsx'
import ModeToggle from './ModeToggle.jsx'

export default function Nav() {
  const { mode } = useContext(ModeContext)

  const links = [
    ['#hero',         'Overview'],
    ['#architecture', 'Architecture'],
    ['#status',       'Status'],
    ['#drills',       'DR Drills'],
    ['#metrics',      'Metrics'],
    ['#evidence',     'Evidence'],
    ...(mode === 'live' ? [['#liveops', 'Live Ops']] : []),
    ['#followup',     'Follow-up'],
  ]

  return (
    <nav
      className={`sticky top-0 z-50 border-b transition-colors ${
        mode === 'live'
          ? 'border-red-900/40'
          : 'border-white/5'
      }`}
      style={{
        background: mode === 'live'
          ? 'rgba(20,5,5,0.95)'
          : 'rgba(10,15,26,0.92)',
        backdropFilter: 'blur(12px)',
      }}
    >
      <div className="max-w-6xl mx-auto px-6 flex items-center gap-1 overflow-x-auto"
           style={{ height: '52px' }}>
        <span className="text-sky-400 font-bold text-xs tracking-widest uppercase mr-4 flex-shrink-0">
          CLOPR2 · DR Gateway
        </span>
        {links.map(([href, label]) => (
          <a
            key={href}
            href={href}
            className={`text-xs font-medium px-3 py-1 rounded transition-colors whitespace-nowrap flex-shrink-0 ${
              href === '#liveops'
                ? 'text-red-400 hover:text-red-300 hover:bg-red-950/30'
                : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`}
          >
            {label}
            {href === '#liveops' && (
              <span className="ml-1 w-1.5 h-1.5 rounded-full bg-red-400 inline-block animate-pulse" />
            )}
          </a>
        ))}
        <div className="ml-auto flex-shrink-0 pl-4">
          <ModeToggle />
        </div>
      </div>
    </nav>
  )
}
