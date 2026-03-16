import { motion } from 'framer-motion'

const ITEMS = [
  {
    icon: '🔄',
    status: 'maintenance',
    title: 'Rebuild pg-standby as streaming replica',
    tag: 'Maintenance',
    tagColor: 'text-amber-400 bg-amber-950/50 border-amber-800/40',
    body: `pg-standby (10.0.96.14) is PostgreSQL-active but stuck at LSN 0/542FD18 — the pre-failover timeline. When pg-primary was stopped during full-site failover, pg-standby lost its replication feed and cannot auto-rejoin the new timeline.`,
    fix: 'Run pg_basebackup on pg-standby from the restored pg-primary, then start PostgreSQL with standby.signal. Until resolved, on-prem HA runs on a single node (pg-primary).',
    nonGate: true,
  },
  {
    icon: '🔑',
    status: 'note',
    title: 'Add SSH ControlMaster pre-check to runbooks',
    tag: 'Process',
    tagColor: 'text-sky-400 bg-sky-950/50 border-sky-800/40',
    body: 'The WSL SSH ControlMaster socket at ~/.ssh/ctl/pve goes stale when WSL changes network context. This caused mid-execution SSH failure during the failover drill, adding ~45 min to RTO.',
    fix: 'Add: rm -f ~/.ssh/ctl/pve && ssh pve echo ok as a mandatory pre-step in both failover and failback runbooks.',
    nonGate: false,
  },
  {
    icon: '💰',
    status: 'note',
    title: 'Re-enable Azure auto-shutdown on vm-pg-dr-fce',
    tag: 'Cost',
    tagColor: 'text-sky-400 bg-sky-950/50 border-sky-800/40',
    body: 'Auto-shutdown was disabled before the DR drill to prevent the VM from stopping mid-execution. Verify it has been re-enabled at the desired schedule.',
    fix: 'Portal: vm-pg-dr-fce → Auto-shutdown → re-enable at preferred time.',
    nonGate: false,
  },
  {
    icon: '✅',
    status: 'complete',
    title: 'S4-09 COMPLETE — all acceptance criteria met',
    tag: 'COMPLETE',
    tagColor: 'text-emerald-400 bg-emerald-950/50 border-emerald-800/40',
    body: 'Failover PASS (commit c8063d4) · Failback PASS (commit d59b7ae) · RPO 0 bytes · 33 evidence files · ClickUp task 86c8u3pwy updated.',
    fix: null,
    nonGate: false,
  },
]

export default function FollowUp() {
  return (
    <div className="space-y-4">
      {ITEMS.map((item, i) => (
        <motion.div
          key={item.title}
          className={`flex gap-4 rounded-xl border p-5 ${
            item.status === 'complete'
              ? 'border-emerald-900/50 bg-emerald-950/20'
              : 'border-white/8'
          }`}
          style={item.status !== 'complete' ? { background: 'rgba(17,24,39,0.8)' } : {}}
          initial={{ opacity: 0, x: -12 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: .3, delay: i * .08 }}
        >
          <span className="text-2xl flex-shrink-0 mt-0.5">{item.icon}</span>
          <div className="flex-1 min-w-0">
            <div className="flex flex-wrap items-center gap-2 mb-2">
              <h3 className="font-semibold text-white text-sm">{item.title}</h3>
              <span className={`text-xs font-bold px-2 py-0.5 rounded-md border ${item.tagColor}`}>
                {item.tag}
              </span>
              {item.nonGate && (
                <span className="text-xs px-2 py-0.5 rounded-md border border-slate-700 text-slate-400">
                  Non-gate
                </span>
              )}
            </div>
            <p className="text-sm text-slate-400 leading-relaxed mb-2">{item.body}</p>
            {item.fix && (
              <div className="rounded-lg px-3 py-2 border border-white/5"
                   style={{ background: 'rgba(0,0,0,0.3)' }}>
                <p className="text-xs text-slate-400">
                  <span className="text-sky-400 font-semibold">Fix: </span>
                  {item.fix}
                </p>
              </div>
            )}
          </div>
        </motion.div>
      ))}
    </div>
  )
}
