import { useState, useEffect } from 'react'
import { motion } from 'framer-motion'

const FALLBACK_METRICS = {
  onprem_failover:   { rto_label: '<1s',   rto_sublabel: 'VRRP · <5s app-confirmed',            rpo_label: 'N/A',    date: '2026-03-14', sprint: 'S4-03', verdict: 'PASS' },
  onprem_fallback:   { rto_label: '24s',   rto_sublabel: 'Replication resumed automatically',     rpo_label: '0 bytes', date: '2026-03-14', sprint: 'S4-03', verdict: 'PASS' },
  fullsite_failover: { rto_label: '32s',   rto_sublabel: 'S5-01 automated · fullsite-failover.sh', rpo_label: '0 bytes', date: '2026-03-16', sprint: 'S5-01', verdict: 'PASS', note: 'Previous manual: 48m 42s (SSH interruption). Automated: 32s.' },
  fullsite_failback: { rto_label: '103s',  rto_sublabel: 'S5-01 automated · app RTO (service 71s)', rpo_label: '0 bytes', date: '2026-03-16', sprint: 'S5-01', verdict: 'PASS', note: 'Service RTO 71s · App RTO 103s · Topology RTO 57s' },
  evidence_files: 51,
  commits: ['a386281', '217b7c6'],
}

const CARD_META = [
  { key: 'onprem_failover',  title: 'On-Prem Failover',   color: 'text-emerald-400', border: 'border-emerald-900/50', accent: '#22c55e' },
  { key: 'onprem_fallback',  title: 'On-Prem Fallback',   color: 'text-sky-400',     border: 'border-sky-900/50',     accent: '#38bdf8' },
  { key: 'fullsite_failover',title: 'Full-Site Failover', color: 'text-amber-400',   border: 'border-amber-900/50',   accent: '#f59e0b' },
  { key: 'fullsite_failback',title: 'Full-Site Fallback', color: 'text-violet-400',  border: 'border-violet-900/50',  accent: '#a78bfa' },
]

// Semicircle RTO gauge
function RtoGauge({ rtoLabel, accent }) {
  // Parse RTO for gauge fill: <1s=green, <60s=emerald, <120s=amber, else red
  const rtoSeconds = (() => {
    if (!rtoLabel) return null
    if (rtoLabel.includes('<')) return 1
    const n = parseInt(rtoLabel)
    return isNaN(n) ? null : n
  })()

  const fill = rtoSeconds === null ? 0.5
    : rtoSeconds <= 5   ? 0.08
    : rtoSeconds <= 30  ? 0.15
    : rtoSeconds <= 60  ? 0.30
    : rtoSeconds <= 120 ? 0.55
    : rtoSeconds <= 300 ? 0.75
    : 0.95

  const r = 30, cx = 40, cy = 40
  const startAngle = 180, sweep = 180 * fill
  const endAngle = startAngle + sweep
  const toRad = (a) => (a * Math.PI) / 180
  const ex = cx + r * Math.cos(toRad(endAngle))
  const ey = cy + r * Math.sin(toRad(endAngle))
  const bgEnd = cx + r * Math.cos(toRad(360))
  const bgEy  = cy + r * Math.sin(toRad(360))

  return (
    <svg width="80" height="44" viewBox="0 0 80 44" className="overflow-visible">
      {/* Background arc */}
      <path
        d={`M ${cx - r} ${cy} A ${r} ${r} 0 0 1 ${cx + r} ${cy}`}
        fill="none" stroke="#1e293b" strokeWidth="5" strokeLinecap="round"
      />
      {/* Fill arc */}
      {fill > 0 && (
        <path
          d={`M ${cx - r} ${cy} A ${r} ${r} 0 ${fill > 0.5 ? 1 : 0} 1 ${ex} ${ey}`}
          fill="none" stroke={accent} strokeWidth="5" strokeLinecap="round"
          style={{ opacity: 0.85 }}
        />
      )}
    </svg>
  )
}

export default function MetricsPanel({ metrics }) {
  const m = metrics || FALLBACK_METRICS

  return (
    <div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {CARD_META.map((meta, i) => {
          const d = m[meta.key]
          if (!d) return null
          return (
            <motion.div
              key={meta.key}
              className={`rounded-xl border ${meta.border} p-5 relative overflow-hidden`}
              style={{ background: 'rgba(17,24,39,0.9)' }}
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.35, delay: i * 0.08 }}
            >
              {/* Top accent bar */}
              <div className="absolute top-0 left-0 right-0 h-0.5" style={{ background: meta.accent }} />

              <div className="flex items-start justify-between mb-2">
                <p className="text-xs text-slate-500 font-semibold uppercase tracking-wide">
                  {meta.title}
                </p>
                {d.sprint === 'S5-01' && (
                  <span className="text-xs text-emerald-400 bg-emerald-950/60 border border-emerald-900/40 px-1.5 py-0.5 rounded font-bold">
                    Automated
                  </span>
                )}
              </div>

              <div className="flex items-end gap-3 mb-1">
                <p className={`text-3xl font-extrabold ${meta.color}`}>{d.rto_label}</p>
                <RtoGauge rtoLabel={d.rto_label} accent={meta.accent} />
              </div>

              <p className="text-xs text-slate-500 mb-3 leading-snug">{d.rto_sublabel}</p>

              {d.note && (
                <p className="text-xs text-slate-600 mb-3 leading-snug border-l-2 border-white/10 pl-2">
                  {d.note}
                </p>
              )}

              <div className="flex justify-between items-end border-t border-white/5 pt-3">
                <div>
                  <p className="text-xs text-slate-500">RPO</p>
                  <p className="text-sm font-bold text-sky-400">{d.rpo_label}</p>
                </div>
                <div className="text-right">
                  <p className="text-xs text-slate-500">{d.sprint} · {d.date}</p>
                  <p className="text-xs font-bold text-emerald-400">{d.verdict}</p>
                </div>
              </div>
            </motion.div>
          )
        })}
      </div>

      {/* Summary row */}
      <motion.div
        className="grid grid-cols-1 sm:grid-cols-3 gap-4"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.5 }}
      >
        <SummaryCard
          label="RPO — all drills"
          value="0 bytes"
          sub="Zero data loss confirmed at every promotion"
          color="text-emerald-400"
        />
        <SummaryCard
          label="Evidence committed"
          value={`${m.evidence_files} files`}
          sub={`Commits: ${(m.commits || []).join(', ')}`}
          color="text-sky-400"
        />
        <div className="rounded-xl border border-white/8 p-5"
             style={{ background: 'rgba(17,24,39,0.9)' }}>
          <p className="text-xs text-slate-500 font-semibold uppercase tracking-wide mb-3">
            S5-01 Automation note
          </p>
          <p className="text-xs text-slate-400 leading-relaxed">
            Scripts in <span className="font-mono text-sky-400">scripts/dr/</span> fully automate
            all four drills. Previous manual full-site failover was{' '}
            <span className="text-amber-400 font-bold">48m 42s</span> (SSH interruption).
            Automated RTO: <span className="text-emerald-400 font-bold">32s</span>.
          </p>
        </div>
      </motion.div>
    </div>
  )
}

function SummaryCard({ label, value, sub, color }) {
  return (
    <div className="rounded-xl border border-white/8 p-5" style={{ background: 'rgba(17,24,39,0.9)' }}>
      <p className="text-xs text-slate-500 font-semibold uppercase tracking-wide mb-2">{label}</p>
      <p className={`text-2xl font-extrabold ${color} mb-1`}>{value}</p>
      <p className="text-xs text-slate-500">{sub}</p>
    </div>
  )
}
