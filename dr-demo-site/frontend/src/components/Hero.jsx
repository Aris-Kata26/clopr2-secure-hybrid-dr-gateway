import { useState, useEffect, useContext } from 'react'
import { motion } from 'framer-motion'
import { ModeContext } from '../App.jsx'

const BADGES = [
  { label: '✓ Full-Site Failover PASS', color: 'text-emerald-400 border-emerald-800 bg-emerald-950/50' },
  { label: '✓ Full-Site Fallback PASS', color: 'text-emerald-400 border-emerald-800 bg-emerald-950/50' },
  { label: 'RPO 0 bytes',              color: 'text-sky-400    border-sky-800    bg-sky-950/50'   },
  { label: 'PostgreSQL 16',            color: 'text-sky-400    border-sky-800    bg-sky-950/50'   },
  { label: 'WireGuard VPN',            color: 'text-violet-400 border-violet-800 bg-violet-950/50'},
  { label: 'Keepalived VRRP',          color: 'text-violet-400 border-violet-800 bg-violet-950/50'},
  { label: 'Terraform + Ansible',      color: 'text-amber-400  border-amber-800  bg-amber-950/50' },
  { label: 'Azure + Proxmox',          color: 'text-amber-400  border-amber-800  bg-amber-950/50' },
  { label: 'S5-01 Automated',          color: 'text-emerald-400 border-emerald-700 bg-emerald-950/50' },
]

// Animated count-up hook
function useCountUp(target, duration = 1200, suffix = '') {
  const [value, setValue] = useState(0)
  useEffect(() => {
    if (typeof target !== 'number') return
    let start = null
    const step = (ts) => {
      if (!start) start = ts
      const progress = Math.min((ts - start) / duration, 1)
      // easeOutCubic
      const eased = 1 - Math.pow(1 - progress, 3)
      setValue(Math.floor(eased * target))
      if (progress < 1) requestAnimationFrame(step)
      else setValue(target)
    }
    const id = requestAnimationFrame(step)
    return () => cancelAnimationFrame(id)
  }, [target, duration])
  return value
}

const STATS = [
  { numericValue: null, displayValue: '<1s',  label: 'On-prem failover RTO', color: '#22c55e' },
  { numericValue: 0,   displayValue: null,    label: 'RPO bytes all drills',  color: '#38bdf8' },
  { numericValue: 32,  displayValue: null,    label: 'Full-site failover RTO (s)', color: '#a78bfa', suffix: 's' },
  { numericValue: 103, displayValue: null,    label: 'Full-site fallback app RTO (s)', color: '#f59e0b', suffix: 's' },
]

function StatCard({ stat, index }) {
  const count = useCountUp(stat.numericValue ?? 0, 1200 + index * 200)
  const display = stat.displayValue ?? `${count}${stat.suffix || ''}`

  return (
    <motion.div
      className="rounded-xl border border-white/8 p-4 relative overflow-hidden"
      style={{ background: 'rgba(17,24,39,0.7)' }}
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay: 0.7 + index * 0.1 }}
    >
      {/* Accent glow */}
      <div className="absolute bottom-0 left-0 right-0 h-0.5 opacity-60"
           style={{ background: stat.color }} />
      <p className="text-3xl font-extrabold mb-1" style={{ color: stat.color }}>
        {display}
      </p>
      <p className="text-xs text-slate-400 font-medium leading-snug">{stat.label}</p>
    </motion.div>
  )
}

export default function Hero({ mode }) {
  const { modeInfo } = useContext(ModeContext)

  return (
    <div
      className="relative overflow-hidden pt-20 pb-24 px-6"
      style={{
        background: mode === 'live'
          ? 'radial-gradient(ellipse 90% 60% at 50% -5%, rgba(239,68,68,0.06), transparent)'
          : 'radial-gradient(ellipse 90% 60% at 50% -5%, rgba(14,165,233,0.10), transparent)',
      }}
    >
      <GridLines mode={mode} />

      <div className="max-w-6xl mx-auto relative z-10">
        {/* Mode pill */}
        <motion.div
          className="flex items-center gap-3 mb-6"
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4 }}
        >
          <p className="text-xs font-bold tracking-widest uppercase text-sky-400">
            KATAR711 · BCLC24 · Sprint S5-01
          </p>
          {mode === 'live' ? (
            <span className="text-xs font-bold px-3 py-1 rounded-full border border-red-700 bg-red-950/60 text-red-400 flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-red-400 animate-pulse" />
              LIVE MODE — REAL INFRA CONNECTED
            </span>
          ) : (
            <span className="text-xs font-bold px-3 py-1 rounded-full border border-sky-800 bg-sky-950/40 text-sky-400">
              DEMO MODE — Evidence Replay
            </span>
          )}
        </motion.div>

        <motion.h1
          className="text-4xl sm:text-5xl lg:text-6xl font-extrabold leading-tight mb-4"
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, delay: 0.1 }}
        >
          <span className="text-white">Zero-RPO</span>
          <br />
          <span
            className="bg-clip-text text-transparent"
            style={{
              backgroundImage: mode === 'live'
                ? 'linear-gradient(135deg, #f87171 0%, #fb923c 50%, #fbbf24 100%)'
                : 'linear-gradient(135deg, #38bdf8 0%, #818cf8 50%, #22c55e 100%)',
            }}
          >
            Disaster Recovery
          </span>
        </motion.h1>

        <motion.p
          className="text-slate-400 text-lg max-w-2xl mb-2"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.3 }}
        >
          Secure Hybrid DR Gateway (IaC Edition) — Proxmox on-prem + Azure cloud
        </motion.p>

        <motion.p
          className="text-slate-500 text-base max-w-xl mb-10"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.4 }}
        >
          Four-drill validation: on-prem HA + full-site failover/fallback.
          Scripts fully automated in S5-01. RTO 32s · RPO 0 bytes.
        </motion.p>

        {/* Badges */}
        <motion.div
          className="flex flex-wrap gap-2 mb-14"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.5 }}
        >
          {BADGES.map(b => (
            <span key={b.label}
                  className={`text-xs font-semibold px-3 py-1 rounded-md border ${b.color}`}>
              {b.label}
            </span>
          ))}
        </motion.div>

        {/* Stat row */}
        <motion.div
          className="grid grid-cols-2 sm:grid-cols-4 gap-4"
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.6 }}
        >
          {STATS.map((s, i) => <StatCard key={s.label} stat={s} index={i} />)}
        </motion.div>
      </div>
    </div>
  )
}

function GridLines({ mode }) {
  return (
    <svg className="absolute inset-0 w-full h-full pointer-events-none opacity-10"
         xmlns="http://www.w3.org/2000/svg">
      <defs>
        <pattern id="grid" width="48" height="48" patternUnits="userSpaceOnUse">
          <path d="M 48 0 L 0 0 0 48" fill="none"
                stroke={mode === 'live' ? '#4a1515' : '#334155'}
                strokeWidth="0.5" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill="url(#grid)" />
    </svg>
  )
}
