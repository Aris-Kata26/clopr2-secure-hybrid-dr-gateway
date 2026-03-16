import { motion } from 'framer-motion'

const BADGES = [
  { label: '✓ Failover PASS',   color: 'text-emerald-400 border-emerald-800 bg-emerald-950/50' },
  { label: '✓ Failback PASS',   color: 'text-emerald-400 border-emerald-800 bg-emerald-950/50' },
  { label: 'RPO 0 bytes',       color: 'text-sky-400    border-sky-800    bg-sky-950/50'   },
  { label: 'PostgreSQL 16',     color: 'text-sky-400    border-sky-800    bg-sky-950/50'   },
  { label: 'WireGuard VPN',     color: 'text-violet-400 border-violet-800 bg-violet-950/50'},
  { label: 'Keepalived VRRP',   color: 'text-violet-400 border-violet-800 bg-violet-950/50'},
  { label: 'Terraform + Ansible', color: 'text-amber-400  border-amber-800  bg-amber-950/50' },
  { label: 'Azure + Proxmox',   color: 'text-amber-400  border-amber-800  bg-amber-950/50' },
]

const STATS = [
  { value: '<1s',    label: 'On-prem failover RTO' },
  { value: '0',      label: 'RPO bytes (all drills)' },
  { value: '20m 53s',label: 'Full-site failback RTO' },
  { value: '33',     label: 'Evidence files' },
]

export default function Hero() {
  return (
    <div
      className="relative overflow-hidden pt-20 pb-24 px-6"
      style={{
        background: 'radial-gradient(ellipse 90% 60% at 50% -5%, rgba(14,165,233,0.10), transparent)',
      }}
    >
      {/* Animated grid background */}
      <GridLines />

      <div className="max-w-6xl mx-auto relative z-10">
        <motion.p
          className="text-xs font-bold tracking-widest uppercase text-sky-400 mb-4"
          initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: .4 }}
        >
          KATAR711 · BCLC24 · Sprint 4 — S4-03 / S4-09
        </motion.p>

        <motion.h1
          className="text-4xl sm:text-5xl lg:text-6xl font-extrabold leading-tight mb-4"
          initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: .5, delay: .1 }}
        >
          <span className="text-white">Secure Hybrid</span>
          <br />
          <span
            className="bg-clip-text text-transparent"
            style={{ backgroundImage: 'linear-gradient(135deg, #38bdf8 0%, #818cf8 50%, #22c55e 100%)' }}
          >
            DR Gateway
          </span>
        </motion.h1>

        <motion.p
          className="text-slate-400 text-lg max-w-2xl mb-3"
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: .3 }}
        >
          IaC Edition — Proxmox on-prem + Azure cloud
        </motion.p>

        <motion.p
          className="text-slate-500 text-base max-w-xl mb-10"
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: .4 }}
        >
          Full-cycle DR validation: on-prem HA failover/fallback and full-site failover to
          Azure then failback — all captured with live evidence.
        </motion.p>

        {/* Badges */}
        <motion.div
          className="flex flex-wrap gap-2 mb-14"
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: .5 }}
        >
          {BADGES.map(b => (
            <span
              key={b.label}
              className={`text-xs font-semibold px-3 py-1 rounded-md border ${b.color}`}
            >
              {b.label}
            </span>
          ))}
        </motion.div>

        {/* Stat row */}
        <motion.div
          className="grid grid-cols-2 sm:grid-cols-4 gap-4"
          initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: .6 }}
        >
          {STATS.map((s, i) => (
            <motion.div
              key={s.label}
              className="rounded-xl border border-white/8 p-4"
              style={{ background: 'rgba(30,41,59,0.6)' }}
              initial={{ opacity: 0, scale: .95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: .7 + i * .08 }}
            >
              <p
                className="text-3xl font-extrabold mb-1"
                style={{ color: ['#22c55e','#38bdf8','#a78bfa','#f59e0b'][i] }}
              >
                {s.value}
              </p>
              <p className="text-xs text-slate-400 font-medium">{s.label}</p>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </div>
  )
}

function GridLines() {
  return (
    <svg
      className="absolute inset-0 w-full h-full pointer-events-none opacity-10"
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <pattern id="grid" width="48" height="48" patternUnits="userSpaceOnUse">
          <path d="M 48 0 L 0 0 0 48" fill="none" stroke="#334155" strokeWidth="0.5" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill="url(#grid)" />
    </svg>
  )
}
