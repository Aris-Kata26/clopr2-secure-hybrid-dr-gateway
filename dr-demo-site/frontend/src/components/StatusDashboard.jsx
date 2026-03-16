import { useState, useEffect } from 'react'
import { motion } from 'framer-motion'

const STATUS_COLORS = {
  healthy:  { dot: 'bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.8)]', text: 'text-emerald-400', label: 'HEALTHY' },
  degraded: { dot: 'bg-amber-400  shadow-[0_0_6px_rgba(251,191,36,0.8)]',  text: 'text-amber-400',  label: 'DEGRADED' },
  stopped:  { dot: 'bg-slate-500',                                          text: 'text-slate-400',  label: 'STOPPED' },
  active:   { dot: 'bg-sky-400    shadow-[0_0_6px_rgba(56,189,248,0.6)]',  text: 'text-sky-400',    label: 'ACTIVE' },
  needs_rebuild: { dot: 'bg-amber-400 shadow-[0_0_6px_rgba(251,191,36,0.8)]', text: 'text-amber-400', label: 'NEEDS REBUILD' },
}

const FALLBACK_STATUS = {
  source: 'evidence',
  as_of: '2026-03-16T15:00:00Z',
  components: {
    pg_primary: { host: '10.0.96.11', role: 'primary', status: 'healthy',
      detail: 'pg_is_in_recovery=f · Keepalived MASTER · VIP active · LSN 0/B000358' },
    vm_pg_dr:   { host: '10.200.0.2', role: 'replica', status: 'healthy',
      detail: 'pg_is_in_recovery=t · streaming 0 lag from pg-primary' },
    app_onprem: { host: '10.0.96.13:8080', status: 'healthy',
      health: { status:'ok', db:'ok', db_host:'10.0.96.10', pg_is_in_recovery: false, app_env:'dev', ts:'2026-03-16T15:00:00Z' },
      detail: 'docker-app-1 running · /health 200' },
    pg_standby: { host: '10.0.96.14', role: 'replica', status: 'healthy',
      detail: 'pg_is_in_recovery=t · rebuilt S5-01 · streaming 0 lag' },
    wireguard:  { status: 'active',
      detail: 'Handshake 15s · 34.25 MiB rx / 39.78 MiB tx · keepalive 25s' },
  },
  drill_summary: {
    last_failover_date: '2026-03-16', last_failover_verdict: 'PASS',
    last_failback_date: '2026-03-16', last_failback_verdict: 'PASS',
    rpo_bytes: 0, current_mode: 'normal',
  },
}

export default function StatusDashboard({ status }) {
  const [secondsAgo, setSecondsAgo] = useState(0)

  useEffect(() => {
    setSecondsAgo(0)
    const id = setInterval(() => setSecondsAgo(s => s + 1), 1000)
    return () => clearInterval(id)
  }, [status])

  const data  = status || FALLBACK_STATUS
  const comps = data.components
  const drill = data.drill_summary

  const cards = [
    {
      key: 'pg_primary', title: 'pg-primary', icon: '🐘',
      status: comps.pg_primary.status,
      meta: [
        { k: 'Host',       v: comps.pg_primary.host },
        { k: 'Role',       v: 'PRIMARY' },
        { k: 'Keepalived', v: 'MASTER' },
        { k: 'VIP',        v: '10.0.96.10 ●' },
        { k: 'WG handshake', v: '15s ago' },
      ],
      detail: comps.pg_primary.detail,
    },
    {
      key: 'vm_pg_dr', title: 'vm-pg-dr-fce', icon: '☁',
      status: comps.vm_pg_dr.status,
      meta: [
        { k: 'Host',     v: comps.vm_pg_dr.host },
        { k: 'Role',     v: 'REPLICA' },
        { k: 'Lag',      v: '0 bytes' },
        { k: 'Provider', v: 'Azure francecentral' },
      ],
      detail: comps.vm_pg_dr.detail,
    },
    {
      key: 'app_onprem', title: 'app-onprem', icon: '⚡',
      status: comps.app_onprem.status,
      meta: [
        { k: 'Host',     v: comps.app_onprem.host },
        { k: 'DB host',  v: '10.0.96.10 (VIP)' },
        { k: 'Recovery', v: 'false (on primary)' },
        { k: 'Env',      v: 'dev' },
      ],
      detail: comps.app_onprem.detail,
      healthJson: comps.app_onprem.health,
    },
    {
      key: 'pg_standby', title: 'pg-standby', icon: '🔄',
      status: comps.pg_standby.status,
      meta: [
        { k: 'Host',   v: comps.pg_standby.host },
        { k: 'Role',   v: 'REPLICA' },
        { k: 'Lag',    v: '0 bytes' },
        { k: 'Rebuilt', v: 'S5-01 (2026-03-16)' },
      ],
      detail: comps.pg_standby.detail,
    },
    {
      key: 'wireguard', title: 'WireGuard', icon: '🔐',
      status: comps.wireguard.status,
      meta: [
        { k: 'Endpoint',  v: '20.216.128.32:51820' },
        { k: 'Handshake', v: '15s ago' },
        { k: 'Rx',        v: '34.25 MiB' },
        { k: 'Tx',        v: '39.78 MiB' },
      ],
      detail: comps.wireguard.detail,
    },
    {
      key: 'drill', title: 'Last DR Drills', icon: '✅',
      status: 'healthy',
      meta: [
        { k: 'Failover', v: `${drill.last_failover_verdict} — ${drill.last_failover_date}` },
        { k: 'Failback', v: `${drill.last_failback_verdict} — ${drill.last_failback_date}` },
        { k: 'RPO',      v: `${drill.rpo_bytes} bytes` },
        { k: 'Sprint',   v: 'S5-01 (automated)' },
      ],
      detail: 'All acceptance criteria met. Failover 32s · Fallback 103s · RPO 0 bytes.',
    },
  ]

  return (
    <div>
      {/* Data source header */}
      <div className="flex items-center gap-3 mb-5 flex-wrap">
        <span className="text-xs text-slate-500">
          As of: <span className="text-slate-300 font-mono">{data.as_of}</span>
        </span>
        <span className={`text-xs px-2 py-0.5 rounded font-semibold border ${
          data.source === 'live'
            ? 'bg-emerald-950 text-emerald-400 border-emerald-800 animate-pulse'
            : 'bg-slate-800 text-slate-400 border-slate-700'
        }`}>
          {data.source === 'live' ? '● LIVE' : '● FROM EVIDENCE'}
        </span>
        {data.source !== 'live' && (
          <span className="text-xs text-slate-600">
            Refreshed {secondsAgo}s ago · polls every 20s
          </span>
        )}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {cards.map((card, i) => (
          <StatusCard key={card.key} card={card} index={i} />
        ))}
      </div>
    </div>
  )
}

function StatusCard({ card, index }) {
  const sc = STATUS_COLORS[card.status] || STATUS_COLORS.stopped

  return (
    <motion.div
      className="rounded-xl border border-white/8 p-4"
      style={{ background: 'rgba(17,24,39,0.8)' }}
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, delay: index * 0.06 }}
      layout
    >
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <span>{card.icon}</span>
          <span className="font-mono text-sm font-semibold text-white">{card.title}</span>
        </div>
        <div className="flex items-center gap-1.5">
          <span className={`w-2 h-2 rounded-full ${sc.dot}`} />
          <span className={`text-xs font-bold ${sc.text}`}>{sc.label}</span>
        </div>
      </div>

      <div className="space-y-1 mb-3">
        {card.meta.map(m => (
          <div key={m.k} className="flex justify-between text-xs">
            <span className="text-slate-500">{m.k}</span>
            <span className="text-slate-300 font-mono text-right ml-2 truncate max-w-[160px]">{m.v}</span>
          </div>
        ))}
      </div>

      {card.healthJson && (
        <div className="mt-2 p-2 rounded-md text-xs font-mono overflow-x-auto"
             style={{ background: 'rgba(0,0,0,0.4)' }}>
          <JsonHighlight obj={card.healthJson} />
        </div>
      )}

      <p className="text-xs text-slate-500 mt-2 leading-snug">{card.detail}</p>
    </motion.div>
  )
}

function JsonHighlight({ obj }) {
  const lines = JSON.stringify(obj, null, 2).split('\n')
  return (
    <pre className="leading-relaxed">
      {lines.map((line, i) => {
        const colored = line
          .replace(/"([\w_]+)":/g, (m, k) => `<span class="text-sky-300">"${k}":</span>`)
          .replace(/:\s*(true)/g,   (m, v) => `: <span class="text-emerald-400 font-bold">${v}</span>`)
          .replace(/:\s*(false)/g,  (m, v) => `: <span class="text-red-400 font-bold">${v}</span>`)
          .replace(/:\s*"([^"]+)"/g,(m, v) => `: <span class="text-emerald-300">"${v}"</span>`)
        return <span key={i} dangerouslySetInnerHTML={{ __html: colored + '\n' }} />
      })}
    </pre>
  )
}
