import { motion } from 'framer-motion'

const FALLBACK_METRICS = {
  onprem_failover:   { rto_label: '<1s',     rto_sublabel: 'VRRP · <5s app-confirmed',        rpo_label: 'N/A',    date: '2026-03-14', sprint: 'S4-03', verdict: 'PASS' },
  onprem_fallback:   { rto_label: '24s',     rto_sublabel: 'Replication resumed automatically', rpo_label: '0 bytes', date: '2026-03-14', sprint: 'S4-03', verdict: 'PASS' },
  fullsite_failover: { rto_label: '48m 42s', rto_sublabel: 'Operational · <5 min clean',       rpo_label: '0 bytes', date: '2026-03-15', sprint: 'S4-09', verdict: 'PASS' },
  fullsite_failback: { rto_label: '20m 53s', rto_sublabel: '1253s · pg_basebackup + promote',  rpo_label: '0 bytes', date: '2026-03-15', sprint: 'S4-09', verdict: 'PASS' },
  evidence_files: 33,
  commits: ['c8063d4', 'd59b7ae'],
}

const CARD_META = [
  { key: 'onprem_failover',   title: 'On-Prem Failover',    color: 'text-emerald-400', border: 'border-emerald-900', accent: '#22c55e' },
  { key: 'onprem_fallback',   title: 'On-Prem Fallback',    color: 'text-sky-400',     border: 'border-sky-900',     accent: '#38bdf8' },
  { key: 'fullsite_failover', title: 'Full-Site Failover',  color: 'text-amber-400',   border: 'border-amber-900',   accent: '#f59e0b' },
  { key: 'fullsite_failback', title: 'Full-Site Failback',  color: 'text-violet-400',  border: 'border-violet-900',  accent: '#a78bfa' },
]

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
              style={{ background: `rgba(17,24,39,0.9)` }}
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: .35, delay: i * .08 }}
            >
              {/* Top accent bar */}
              <div className="absolute top-0 left-0 right-0 h-0.5"
                   style={{ background: meta.accent }} />

              <p className="text-xs text-slate-500 font-semibold uppercase tracking-wide mb-3">
                {meta.title}
              </p>

              <p className={`text-3xl font-extrabold ${meta.color} mb-1`}>
                {d.rto_label}
              </p>
              <p className="text-xs text-slate-500 mb-4 leading-snug">{d.rto_sublabel}</p>

              <div className="flex justify-between items-end">
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
        initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: .5 }}
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
          <p className="text-xs text-slate-500 font-semibold uppercase tracking-wide mb-3">Failover RTO note</p>
          <p className="text-xs text-slate-400 leading-relaxed">
            Operational RTO of <span className="text-amber-400 font-bold">48m 42s</span> was caused
            by WSL losing route to PVE mid-execution. Steps completed via Azure run-command.
            Clean RTO estimate: <span className="text-emerald-400 font-bold">&lt;5 minutes</span>.
            Outcome was not affected.
          </p>
        </div>
      </motion.div>
    </div>
  )
}

function SummaryCard({ label, value, sub, color }) {
  return (
    <div className="rounded-xl border border-white/8 p-5"
         style={{ background: 'rgba(17,24,39,0.9)' }}>
      <p className="text-xs text-slate-500 font-semibold uppercase tracking-wide mb-2">{label}</p>
      <p className={`text-2xl font-extrabold ${color} mb-1`}>{value}</p>
      <p className="text-xs text-slate-500">{sub}</p>
    </div>
  )
}
