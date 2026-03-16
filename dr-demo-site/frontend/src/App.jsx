import { useState, useEffect, createContext } from 'react'
import Nav from './components/Nav.jsx'
import Hero from './components/Hero.jsx'
import ArchDiagram from './components/ArchDiagram.jsx'
import StatusDashboard from './components/StatusDashboard.jsx'
import DrillPanel from './components/DrillPanel.jsx'
import MetricsPanel from './components/MetricsPanel.jsx'
import EvidenceViewer from './components/EvidenceViewer.jsx'
import FollowUp from './components/FollowUp.jsx'
import LiveOpsPanel from './components/LiveOpsPanel.jsx'

export const ModeContext = createContext({
  mode: 'demo',
  setMode: () => {},
  modeInfo: null,
})

export default function App() {
  const [status, setStatus]       = useState(null)
  const [metrics, setMetrics]     = useState(null)
  const [activeDrill, setActiveDrill] = useState('onprem-failover')
  const [mode, setModeState]      = useState(() => {
    try { return localStorage.getItem('dr-demo-mode') || 'demo' } catch { return 'demo' }
  })
  const [modeInfo, setModeInfo]   = useState(null)

  const setMode = (m) => {
    setModeState(m)
    try { localStorage.setItem('dr-demo-mode', m) } catch {}
  }

  useEffect(() => {
    const fetchStatus = () =>
      fetch('/api/status').then(r => r.json()).then(setStatus).catch(() => {})
    const fetchMetrics = () =>
      fetch('/api/metrics').then(r => r.json()).then(setMetrics).catch(() => {})
    const fetchMode = () =>
      fetch('/api/mode').then(r => r.json()).then(d => {
        setModeInfo(d)
        // If live mode no longer available, drop back to demo
        if (!d.live_enabled && mode === 'live') setMode('demo')
      }).catch(() => {})

    fetchStatus()
    fetchMetrics()
    fetchMode()

    const statusId  = setInterval(fetchStatus,  20000)
    const modeId    = setInterval(fetchMode,     30000)
    return () => { clearInterval(statusId); clearInterval(modeId) }
  }, [])

  return (
    <ModeContext.Provider value={{ mode, setMode, modeInfo }}>
      <div className="min-h-screen" style={{ background: 'var(--bg)' }}>
        <Nav mode={mode} />

        <section id="hero">
          <Hero mode={mode} />
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

        {mode === 'live' && (
          <section id="liveops" className="py-20 border-t border-red-900/30"
                   style={{ background: 'rgba(127,29,29,0.04)' }}>
            <div className="max-w-6xl mx-auto px-6">
              <SectionHeader
                eyebrow="07 · Live Operations"
                title="Script execution control plane"
                live
              />
              <LiveOpsPanel />
            </div>
          </section>
        )}

        <section id="followup" className="py-20 border-t border-white/5">
          <div className="max-w-6xl mx-auto px-6">
            <SectionHeader eyebrow={mode === 'live' ? '08 · Follow-up' : '07 · Follow-up'} title="Post-drill maintenance" />
            <FollowUp />
          </div>
        </section>

        <footer className="border-t border-white/5 py-10 text-center text-sm text-slate-500">
          <p className="mb-1">
            <span className="text-slate-300 font-semibold">CLOPR2 Secure Hybrid DR Gateway (IaC Edition)</span>
            {' · '}Owner: <span className="text-slate-300">KATAR711</span>
            {' · '}Team: <span className="text-slate-300">BCLC24</span>
          </p>
          <p>Validated 2026-03-16 · Proxmox · Azure · PostgreSQL 16 · WireGuard · Keepalived · Terraform · Ansible</p>
        </footer>
      </div>
    </ModeContext.Provider>
  )
}

function SectionHeader({ eyebrow, title, live }) {
  return (
    <div className="mb-10">
      <p className={`text-xs font-bold tracking-widest uppercase mb-2 ${
        live ? 'text-red-400' : 'text-sky-400'
      }`}>{eyebrow}</p>
      <h2 className="text-2xl font-bold text-white flex items-center gap-3">
        {title}
        {live && (
          <span className="text-xs font-bold px-2 py-0.5 rounded-full border border-red-700 bg-red-950/50 text-red-400 animate-pulse">
            LIVE
          </span>
        )}
      </h2>
    </div>
  )
}
