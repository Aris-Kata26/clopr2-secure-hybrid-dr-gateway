import { motion, AnimatePresence } from 'framer-motion'

// Colours per phase: which nodes are active/dimmed/promoted
const PHASE_STATES = {
  default: {
    pgPrimary:  { fill: '#22c55e', label: 'MASTER', ring: true },
    pgStandby:  { fill: '#38bdf8', label: 'BACKUP', ring: false },
    appOnprem:  { fill: '#a78bfa', label: 'HEALTHY', ring: true },
    vmPgDr:     { fill: '#f59e0b', label: 'REPLICA', ring: false },
    vip:        'pg-primary',
    replActive: true,
    azureAppActive: false,
  },
  'onprem-failover': {
    pgPrimary:  { fill: '#475569', label: 'STOPPED', ring: false },
    pgStandby:  { fill: '#22c55e', label: 'MASTER ←VIP', ring: true },
    appOnprem:  { fill: '#a78bfa', label: 'SERVING (RO)', ring: true },
    vmPgDr:     { fill: '#f59e0b', label: 'REPLICA', ring: false },
    vip:        'pg-standby',
    replActive: false,
    azureAppActive: false,
  },
  'onprem-fallback': {
    pgPrimary:  { fill: '#22c55e', label: 'MASTER', ring: true },
    pgStandby:  { fill: '#38bdf8', label: 'BACKUP', ring: false },
    appOnprem:  { fill: '#a78bfa', label: 'HEALTHY', ring: true },
    vmPgDr:     { fill: '#f59e0b', label: 'REPLICA', ring: false },
    vip:        'pg-primary',
    replActive: true,
    azureAppActive: false,
  },
  'fullsite-failover': {
    pgPrimary:  { fill: '#475569', label: 'STOPPED', ring: false },
    pgStandby:  { fill: '#475569', label: 'ISOLATED', ring: false },
    appOnprem:  { fill: '#475569', label: 'STOPPED', ring: false },
    vmPgDr:     { fill: '#22c55e', label: 'PRIMARY ★', ring: true },
    vip:        null,
    replActive: true,
    azureAppActive: true,
  },
  'fullsite-failback': {
    pgPrimary:  { fill: '#22c55e', label: 'MASTER', ring: true },
    pgStandby:  { fill: '#ef4444', label: 'NEEDS REBUILD', ring: false },
    appOnprem:  { fill: '#a78bfa', label: 'HEALTHY', ring: true },
    vmPgDr:     { fill: '#38bdf8', label: 'REPLICA', ring: false },
    vip:        'pg-primary',
    replActive: true,
    azureAppActive: false,
  },
}

export default function ArchDiagram({ activeDrill }) {
  const phase = PHASE_STATES[activeDrill] || PHASE_STATES.default

  return (
    <div className="rounded-2xl border border-white/8 overflow-hidden"
         style={{ background: 'rgba(15,23,42,0.8)' }}>

      {/* Phase indicator */}
      <div className="px-5 py-3 border-b border-white/5 flex items-center gap-3">
        <span className="text-xs text-slate-400">Showing topology for:</span>
        <span className="text-xs font-bold text-sky-400 uppercase tracking-wide">
          {activeDrill === 'default' ? 'Normal operation' :
           activeDrill.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}
        </span>
        <span className="ml-auto text-xs text-slate-600">Select a drill phase below to update diagram</span>
      </div>

      {/* SVG diagram */}
      <svg
        viewBox="0 0 960 430"
        xmlns="http://www.w3.org/2000/svg"
        className="w-full"
        style={{ maxHeight: '420px' }}
      >
        {/* ── Definitions ── */}
        <defs>
          <marker id="arrow-green" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
            <path d="M0,0 L0,6 L8,3 z" fill="#22c55e" />
          </marker>
          <marker id="arrow-blue" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
            <path d="M0,0 L0,6 L8,3 z" fill="#38bdf8" />
          </marker>
          <marker id="arrow-amber" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
            <path d="M0,0 L0,6 L8,3 z" fill="#f59e0b" />
          </marker>
          <filter id="glow-green"><feGaussianBlur stdDeviation="3" result="blur"/>
            <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
          </filter>
          <filter id="glow-amber"><feGaussianBlur stdDeviation="3" result="blur"/>
            <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
          </filter>
        </defs>

        {/* ── On-prem zone ── */}
        <rect x="10" y="10" width="490" height="410" rx="14" fill="rgba(16,30,54,0.9)"
              stroke="rgba(56,189,248,0.2)" strokeWidth="1.5" />
        <text x="30" y="38" fill="#38bdf8" fontSize="11" fontWeight="700" letterSpacing="1.5"
              fontFamily="JetBrains Mono, monospace">ON-PREM · PROXMOX</text>

        {/* VIP badge */}
        <VipBadge phase={phase} />

        {/* pg-primary */}
        <Node cx={140} cy={140} label="pg-primary" ip="10.0.96.11"
              role={phase.pgPrimary.label} fill={phase.pgPrimary.fill}
              ring={phase.pgPrimary.ring} filterId="glow-green" />

        {/* pg-standby */}
        <Node cx={140} cy={270} label="pg-standby" ip="10.0.96.14"
              role={phase.pgStandby.label} fill={phase.pgStandby.fill}
              ring={phase.pgStandby.ring} />

        {/* app-onprem */}
        <Node cx={370} cy={200} label="app-onprem" ip="10.0.96.13:8080"
              role={phase.appOnprem.label} fill={phase.appOnprem.fill}
              ring={phase.appOnprem.ring} shape="rounded-rect" />

        {/* pg-primary → pg-standby replication */}
        <ReplicationLine x1={140} y1={172} x2={140} y2={238}
          active={!['onprem-failover','fullsite-failover'].includes(activeDrill)} />

        {/* app-onprem → VIP connection */}
        <AppVipLine phase={phase} />

        {/* ── Gap / WireGuard tunnel ── */}
        <TunnelSection phase={phase} />

        {/* ── Azure zone ── */}
        <rect x="590" y="10" width="360" height="410" rx="14" fill="rgba(30,20,10,0.9)"
              stroke="rgba(245,158,11,0.2)" strokeWidth="1.5" />
        <text x="610" y="38" fill="#f59e0b" fontSize="11" fontWeight="700" letterSpacing="1.5"
              fontFamily="JetBrains Mono, monospace">AZURE · francecentral</text>

        {/* vm-pg-dr-fce */}
        <Node cx={760} cy={160} label="vm-pg-dr-fce" ip="10.200.0.2"
              role={phase.vmPgDr.label} fill={phase.vmPgDr.fill}
              ring={phase.vmPgDr.ring} filterId="glow-amber" />

        {/* Azure app (only visible during full-site failover) */}
        {phase.azureAppActive && (
          <motion.g initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: .4 }}>
            <Node cx={760} cy={310} label="clopr2-app-dr" ip="port 8000 (--network host)"
                  role="ACTIVE" fill="#22c55e" ring shape="rounded-rect" />
            {/* vm → azure app line */}
            <line x1={760} y1={192} x2={760} y2={280} stroke="#22c55e"
                  strokeWidth="1.5" strokeDasharray="4,3" opacity="0.7" />
            <text x={770} y={241} fill="#22c55e" fontSize="10" fontFamily="JetBrains Mono, monospace">FastAPI</text>
          </motion.g>
        )}

        {/* ── Legend ── */}
        <Legend />
      </svg>
    </div>
  )
}

// ── Sub-components ────────────────────────────────────────────────────────────

function Node({ cx, cy, label, ip, role, fill, ring, shape, filterId }) {
  const r = 34
  return (
    <motion.g animate={{ opacity: fill === '#475569' ? 0.4 : 1 }} transition={{ duration: .5 }}>
      {/* Pulse ring for active nodes */}
      {ring && (
        <motion.circle
          cx={cx} cy={cy} r={r + 6}
          fill="none" stroke={fill} strokeWidth="1.5" opacity="0.3"
          animate={{ r: [r + 5, r + 12, r + 5], opacity: [0.3, 0, 0.3] }}
          transition={{ duration: 2.5, repeat: Infinity, ease: 'easeInOut' }}
        />
      )}

      {/* Main circle */}
      <motion.circle
        cx={cx} cy={cy} r={r}
        fill={`${fill}22`} stroke={fill} strokeWidth="2"
        animate={{ stroke: fill }} transition={{ duration: .5 }}
        filter={ring && filterId ? `url(#${filterId})` : undefined}
      />

      {/* Status dot */}
      <motion.circle cx={cx + r - 5} cy={cy - r + 5} r={5}
        fill={fill} animate={{ fill }} transition={{ duration: .5 }} />

      {/* Label */}
      <text x={cx} y={cy - 4} textAnchor="middle" fill="white" fontSize="10.5"
            fontWeight="600" fontFamily="JetBrains Mono, monospace">{label}</text>
      <text x={cx} y={cy + 10} textAnchor="middle" fill="#94a3b8" fontSize="9"
            fontFamily="JetBrains Mono, monospace">{ip}</text>
      <motion.text x={cx} y={cy + 24} textAnchor="middle" fontSize="9" fontWeight="700"
            fontFamily="JetBrains Mono, monospace"
            animate={{ fill }} transition={{ duration: .5 }}>
        {role}
      </motion.text>
    </motion.g>
  )
}

function VipBadge({ phase }) {
  const onPrimary  = phase.vip === 'pg-primary'
  const onStandby  = phase.vip === 'pg-standby'
  const x = onPrimary ? 240 : onStandby ? 240 : 240
  const y = onPrimary ? 110 : onStandby ? 242 : 110
  const opacity = phase.vip ? 1 : 0.15

  return (
    <motion.g animate={{ y: onStandby ? 240 - 110 : 0, opacity }} transition={{ duration: .6 }}
              style={{ originX: '240px', originY: '110px' }}>
      <rect x={210} y={97} width={130} height={26} rx={5}
            fill="rgba(34,197,94,0.12)" stroke="rgba(34,197,94,0.5)" strokeWidth="1.5" />
      <text x={275} y={114} textAnchor="middle" fill="#22c55e" fontSize="10" fontWeight="700"
            fontFamily="JetBrains Mono, monospace">VIP 10.0.96.10</text>
      {/* Arrow from VIP to owning node */}
      <motion.line
        x1={214} y1={110} x2={176} y2={onStandby ? 252 : 140}
        stroke="#22c55e" strokeWidth="1.5" strokeDasharray="3,2" opacity="0.6"
        animate={{ x2: 176, y2: onStandby ? 252 : 140 }} transition={{ duration: .6 }}
      />
    </motion.g>
  )
}

function ReplicationLine({ x1, y1, x2, y2, active }) {
  return (
    <motion.g animate={{ opacity: active ? 1 : 0.15 }} transition={{ duration: .4 }}>
      <line x1={x1} y1={y1} x2={x2} y2={y2} stroke="#1f2d40" strokeWidth="6" />
      <line x1={x1} y1={y1} x2={x2} y2={y2} stroke="#334155" strokeWidth="2" />
      {active && (
        <line x1={x1} y1={y1} x2={x2} y2={y2}
              stroke="#38bdf8" strokeWidth="2"
              strokeDasharray="6,4"
              className="stream-path" />
      )}
      <text x={x1 + 8} y={(y1 + y2) / 2 + 4} fill="#38bdf8" fontSize="9"
            fontFamily="JetBrains Mono, monospace">replication</text>
    </motion.g>
  )
}

function AppVipLine({ phase }) {
  const active = phase.appOnprem.fill !== '#475569'
  return (
    <motion.g animate={{ opacity: active ? 1 : 0.1 }} transition={{ duration: .4 }}>
      <path d="M 336,200 Q 280,180 214,115" fill="none" stroke="#a78bfa"
            strokeWidth="1.5" strokeDasharray="4,3" opacity="0.7" />
      <text x={272} y={172} fill="#a78bfa" fontSize="9" textAnchor="middle"
            fontFamily="JetBrains Mono, monospace">→ VIP :5432</text>
    </motion.g>
  )
}

function TunnelSection({ phase }) {
  const wgActive = phase.vmPgDr.fill !== '#475569'
  const replActive = phase.replActive

  return (
    <g>
      {/* Tunnel background */}
      <rect x="505" y="80" width="80" height="270" rx="6"
            fill="rgba(14,165,233,0.04)" stroke="rgba(14,165,233,0.12)" strokeWidth="1" />
      <text x="545" y="222" textAnchor="middle" fill="#38bdf8" fontSize="9"
            fontWeight="600" fontFamily="JetBrains Mono, monospace"
            transform="rotate(-90, 545, 222)">WireGuard UDP 51820</text>

      {/* WireGuard connection line */}
      <motion.g animate={{ opacity: wgActive ? 1 : 0.15 }} transition={{ duration: .4 }}>
        <line x1="174" y1="140" x2="590" y2="160" stroke="#0c4a6e" strokeWidth="6" />
        <line x1="174" y1="140" x2="590" y2="160" stroke="#0ea5e9" strokeWidth="1.5"
              strokeDasharray="4,3" opacity="0.5" />
        {wgActive && (
          <line x1="174" y1="140" x2="590" y2="160" stroke="#38bdf8" strokeWidth="2"
                strokeDasharray="8,5" className="stream-path-slow" />
        )}
      </motion.g>

      {/* Replication stream (above WG tunnel) */}
      <motion.g animate={{ opacity: replActive ? 1 : 0.1 }} transition={{ duration: .4 }}>
        <path d="M 174,132 C 380,80 410,80 590,152"
              fill="none" stroke="#22c55e" strokeWidth="2"
              strokeDasharray="8,5"
              className={replActive ? "stream-path" : undefined}
              opacity="0.9" />
        <text x="384" y="86" fill="#22c55e" fontSize="9" textAnchor="middle"
              fontFamily="JetBrains Mono, monospace">streaming replication</text>
      </motion.g>

      {/* Handshake indicator */}
      {wgActive && (
        <motion.g initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: .3 }}>
          <circle cx="545" cy="170" r="4" fill="#38bdf8" opacity="0.8">
            <animate attributeName="opacity" values="0.8;0.2;0.8" dur="2s" repeatCount="indefinite" />
          </circle>
          <text x="545" y="190" textAnchor="middle" fill="#38bdf8" fontSize="8"
                fontFamily="JetBrains Mono, monospace">●15s</text>
        </motion.g>
      )}
    </g>
  )
}

function Legend() {
  const items = [
    { color: '#22c55e', label: 'Primary / Healthy' },
    { color: '#38bdf8', label: 'Standby / Replica' },
    { color: '#a78bfa', label: 'Application' },
    { color: '#f59e0b', label: 'Azure DR' },
    { color: '#475569', label: 'Stopped / Isolated' },
  ]
  return (
    <g>
      {items.map((item, i) => (
        <g key={item.label} transform={`translate(${620 + (i % 3) * 110}, ${385 + Math.floor(i / 3) * 16})`}>
          <circle cx="5" cy="5" r="4" fill={item.color} />
          <text x="14" y="9" fill="#64748b" fontSize="9" fontFamily="Inter, sans-serif">{item.label}</text>
        </g>
      ))}
    </g>
  )
}
