import { useState, useEffect } from 'react'
import Nav from './components/Nav.jsx'
import Hero from './components/Hero.jsx'
import ArchDiagram from './components/ArchDiagram.jsx'
import StatusDashboard from './components/StatusDashboard.jsx'
import DrillPanel from './components/DrillPanel.jsx'
import MetricsPanel from './components/MetricsPanel.jsx'
import EvidenceViewer from './components/EvidenceViewer.jsx'
import FollowUp from './components/FollowUp.jsx'

export default function App() {
  const [status, setStatus]   = useState(null)
  const [metrics, setMetrics] = useState(null)
  const [activeDrill, setActiveDrill] = useState('onprem-failover')

  useEffect(() => {
    const fetchStatus = () =>
      fetch('/api/status').then(r => r.json()).then(setStatus).catch(() => {})
    const fetchMetrics = () =>
      fetch('/api/metrics').then(r => r.json()).then(setMetrics).catch(() => {})

    fetchStatus()
    fetchMetrics()
    const id = setInterval(fetchStatus, 20000)
    return () => clearInterval(id)
  }, [])

  return (
    <div className="min-h-screen" style={{ background: 'var(--bg)' }}>
      <Nav />

      <section id="hero">
        <Hero />
      </section>

      <section id="architecture" className="py-20 border-t border-white/5">
        <div className="max-w-6xl mx-auto px-6">
          <SectionHeader eyebrow="02 · Architecture" title="Hybrid DR topology" />
          <ArchDiagram activeDrill={activeDrill} status={status} />
        </div>
      </section>

      <section id="status" className="py-20 border-t border-white/5">
        <div className="max-w-6xl mx-auto px-6">
          <SectionHeader eyebrow="03 · Live Status" title="Current system state" />
          <StatusDashboard status={status} />
        </div>
      </section>

      <section id="drills" className="py-20 border-t border-white/5">
        <div className="max-w-6xl mx-auto px-6">
          <SectionHeader eyebrow="04 · DR Drills" title="Evidence replay — four phases" />
          <DrillPanel activeDrill={activeDrill} onDrillChange={setActiveDrill} />
        </div>
      </section>

      <section id="metrics" className="py-20 border-t border-white/5">
        <div className="max-w-6xl mx-auto px-6">
          <SectionHeader eyebrow="05 · Metrics" title="RTO / RPO results" />
          <MetricsPanel metrics={metrics} />
        </div>
      </section>

      <section id="evidence" className="py-20 border-t border-white/5">
        <div className="max-w-6xl mx-auto px-6">
          <SectionHeader eyebrow="06 · Evidence" title="Live evidence files" />
          <EvidenceViewer />
        </div>
      </section>

      <section id="followup" className="py-20 border-t border-white/5">
        <div className="max-w-6xl mx-auto px-6">
          <SectionHeader eyebrow="07 · Follow-up" title="Post-drill maintenance" />
          <FollowUp />
        </div>
      </section>

      <footer className="border-t border-white/5 py-10 text-center text-sm text-slate-500">
        <p className="mb-1">
          <span className="text-slate-300 font-semibold">CLOPR2 Secure Hybrid DR Gateway (IaC Edition)</span>
          {' · '}Owner: <span className="text-slate-300">KATAR711</span>
          {' · '}Team: <span className="text-slate-300">BCLC24</span>
        </p>
        <p>Validated 2026-03-14 / 2026-03-15 · Proxmox · Azure · PostgreSQL 16 · WireGuard · Keepalived · Terraform · Ansible</p>
      </footer>
    </div>
  )
}

function SectionHeader({ eyebrow, title }) {
  return (
    <div className="mb-10">
      <p className="text-xs font-bold tracking-widest uppercase text-sky-400 mb-2">{eyebrow}</p>
      <h2 className="text-2xl font-bold text-white">{title}</h2>
    </div>
  )
}
