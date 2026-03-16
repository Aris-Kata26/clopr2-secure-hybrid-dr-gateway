export default function Nav() {
  return (
    <nav
      className="sticky top-0 z-50 border-b border-white/5"
      style={{ background: 'rgba(10,15,26,0.92)', backdropFilter: 'blur(12px)' }}
    >
      <div className="max-w-6xl mx-auto px-6 flex items-center h-13 gap-1 overflow-x-auto"
           style={{ height: '52px' }}>
        <span className="text-sky-400 font-bold text-xs tracking-widest uppercase mr-6 flex-shrink-0">
          CLOPR2 · DR Gateway
        </span>
        {[
          ['#hero',         'Overview'],
          ['#architecture', 'Architecture'],
          ['#status',       'Status'],
          ['#drills',       'DR Drills'],
          ['#metrics',      'Metrics'],
          ['#evidence',     'Evidence'],
          ['#followup',     'Follow-up'],
        ].map(([href, label]) => (
          <a
            key={href}
            href={href}
            className="text-slate-400 hover:text-white text-xs font-medium px-3 py-1 rounded
                       hover:bg-white/5 transition-colors whitespace-nowrap flex-shrink-0"
          >
            {label}
          </a>
        ))}
      </div>
    </nav>
  )
}
