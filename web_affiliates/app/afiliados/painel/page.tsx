'use client'

import React, { useState, useEffect } from 'react'
import { 
  LayoutDashboard, Users, DollarSign, Wallet, 
  ExternalLink, Copy, Check, AlertCircle, 
  TrendingUp, BarChart3, ChevronRight 
} from 'lucide-react'
import { 
  BarChart, Bar, XAxis, YAxis, CartesianGrid, 
  Tooltip as RechartsTooltip, ResponsiveContainer, LineChart, Line 
} from 'recharts'

// Mock data for initial states
const performanceData = [
  { name: '01/03', clicks: 45, conv: 2 },
  { name: '05/03', clicks: 52, conv: 3 },
  { name: '10/03', clicks: 38, conv: 1 },
  { name: '15/03', clicks: 65, conv: 5 },
  { name: '20/03', clicks: 48, conv: 2 },
  { name: '23/03', clicks: 70, conv: 4 },
]

export default function AffiliateDashboard() {
  const [status, setStatus] = useState<'pending' | 'active' | 'suspended'>('active')
  const [stripeConnected, setStripeConnected] = useState(false)
  const [copied, setCopied] = useState(false)

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col font-sans text-slate-900">
      {/* Sidebar / Topbar for Mobile */}
      <header className="bg-white border-b px-6 py-4 flex items-center justify-between sticky top-0 z-40 lg:px-12 transition-all">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 bg-primary rounded-lg flex items-center justify-center text-white font-bold">M</div>
          <span className="text-xl font-bold tracking-tight">Painel de <span className="text-primary">Afiliado</span></span>
        </div>
        <div className="flex items-center gap-4">
          <div className="text-right hidden sm:block">
            <p className="text-sm font-bold">João Silva</p>
            <p className="text-xs text-slate-500">joao@markaai.com.br</p>
          </div>
          <div className="w-10 h-10 bg-slate-100 rounded-full border-2 border-white shadow-sm ring-1 ring-slate-100 uppercase flex items-center justify-center font-bold text-slate-600">JS</div>
        </div>
      </header>

      <main className="flex-1 p-6 lg:p-12 max-w-7xl mx-auto w-full space-y-8">
        {/* Status Banners */}
        {status === 'pending' && (
          <div className="bg-amber-50 border border-amber-200 p-4 rounded-2xl flex items-center gap-4 text-amber-800 animate-in slide-in-from-top duration-300">
            <AlertCircle className="shrink-0" />
            <div className="flex-1">
              <p className="font-bold text-sm">Seu cadastro está em análise</p>
              <p className="text-xs opacity-80">Avisaremos por e-mail assim que você puder começar a indicar.</p>
            </div>
          </div>
        )}

        {!stripeConnected && status === 'active' && (
          <div className="bg-primary/5 border border-primary/20 p-6 rounded-3xl flex flex-col md:flex-row items-center gap-6 shadow-sm">
             <div className="w-16 h-16 bg-white rounded-2xl flex items-center justify-center text-primary shrink-0 shadow-inner">
               <Wallet size={32} />
             </div>
             <div className="flex-1 text-center md:text-left space-y-1">
               <h3 className="font-bold text-lg">Conecte sua conta Stripe</h3>
               <p className="text-slate-600 text-sm">Sem essa etapa, suas comissões ficam retidas. Receba seus ganhos automaticamente.</p>
             </div>
             <button className="bg-primary hover:bg-primary-dark text-white px-8 py-3 rounded-xl font-bold shadow-lg shadow-primary/20 transition-all flex items-center gap-2 whitespace-nowrap">
               Conectar com Stripe <ChevronRight size={18} />
             </button>
          </div>
        )}

        {/* Metric Cards */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {[
            { label: 'Total de indicações', value: '154', icon: <Users size={20} />, color: 'bg-blue-500' },
            { label: 'Conversões Ativas', value: '18', icon: <TrendingUp size={20} />, color: 'bg-green-500' },
            { label: 'A receber', value: 'R$ 450,00', icon: <Wallet size={20} />, color: 'bg-primary' },
            { label: 'Total pago', value: 'R$ 1.280,45', icon: <DollarSign size={20} />, color: 'bg-slate-900' },
          ].map((card, i) => (
            <div key={i} className="bg-white p-6 rounded-3xl shadow-sm border border-slate-100 space-y-3 hover:shadow-md transition-shadow">
              <div className="flex items-center justify-between">
                <div className={`${card.color} text-white p-2.5 rounded-2xl`}>{card.icon}</div>
                <span className="text-[10px] bg-slate-100 text-slate-500 px-2 py-0.5 rounded-full font-bold uppercase tracking-wider">Mês Atual</span>
              </div>
              <div>
                <p className="text-slate-400 text-xs font-semibold uppercase">{card.label}</p>
                <p className="text-2xl font-black">{card.value}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Middle Section: Coupon & Chart */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
          {/* Coupon Card */}
          <div className="lg:col-span-5 space-y-6">
            <div className="bg-slate-900 text-white p-8 rounded-[2rem] space-y-8 relative overflow-hidden shadow-xl">
              <div className="absolute top-0 right-0 w-32 h-32 bg-primary/20 blur-3xl rounded-full translate-x-12 -translate-y-12"></div>
              <div className="space-y-1 relative z-10">
                <p className="text-primary font-bold text-sm tracking-widest uppercase">Seu Cupom Exclusivo</p>
                <h2 className="text-3xl font-black">Ganhe por indicar</h2>
              </div>
              
              <div className="bg-white/5 border border-white/10 p-4 rounded-2xl flex items-center justify-between group">
                <code className="text-2xl font-mono font-black tracking-widest text-primary">JOAO1234</code>
                <button 
                  onClick={() => copyToClipboard('JOAO1234')}
                  className="bg-white/10 hover:bg-white/20 p-2.5 rounded-lg transition-all"
                >
                  {copied ? <Check size={20} className="text-green-400" /> : <Copy size={20} />}
                </button>
              </div>

              <div className="space-y-4 pt-4">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-400">Desconto para o cliente</span>
                  <span className="font-bold text-green-400">15% no 1º mês</span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-400">Sua comissão</span>
                  <span className="font-bold">10% recorrente / mês</span>
                </div>
              </div>

              <button className="w-full bg-primary hover:bg-primary-dark py-4 rounded-2xl font-bold flex items-center justify-center gap-2 transition-all group">
                Compartilhar link <ExternalLink size={18} className="group-hover:translate-x-1 transition-transform" />
              </button>
            </div>
          </div>

          {/* Performance Chart */}
          <div className="lg:col-span-7 bg-white p-8 rounded-[2rem] border border-slate-100 shadow-sm space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <BarChart3 className="text-slate-400" />
                <h3 className="font-bold text-lg">Performance da Semana</h3>
              </div>
              <select className="bg-slate-50 border-none rounded-xl text-xs font-bold px-3 py-2 outline-none">
                <option>Últimos 30 dias</option>
                <option>Últimos 7 dias</option>
              </select>
            </div>
            <div className="h-[240px] w-full">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={performanceData}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
                  <XAxis 
                    dataKey="name" 
                    axisLine={false} 
                    tickLine={false} 
                    tick={{ fontSize: 10, fill: '#94a3b8', fontWeight: 600 }}
                  />
                  <YAxis hide />
                  <RechartsTooltip 
                    cursor={{ fill: '#f8fafc' }}
                    contentStyle={{ borderRadius: '16px', border: 'none', boxShadow: '0 10px 15px -3px rgb(0 0 0 / 0.1)' }}
                  />
                  <Bar dataKey="clicks" fill="rgba(109, 40, 217, 0.1)" radius={[6, 6, 0, 0]} />
                  <Bar dataKey="conv" fill="#6D28D9" radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
            <div className="flex items-center gap-6 text-[10px] font-bold uppercase tracking-widest text-slate-400 pt-2">
               <div className="flex items-center gap-2">
                 <div className="w-2.5 h-2.5 rounded-full bg-primary/20"></div>
                 Cligues
               </div>
               <div className="flex items-center gap-2">
                 <div className="w-2.5 h-2.5 rounded-full bg-primary"></div>
                 Conversões
               </div>
            </div>
          </div>
        </div>

        {/* Active Referrals Table */}
        <div className="bg-white rounded-[2rem] border border-slate-100 shadow-sm overflow-hidden">
          <div className="p-8 border-b border-slate-50 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <LayoutDashboard className="text-slate-400" />
              <h3 className="font-bold text-lg">Indicações Ativas</h3>
            </div>
            <button className="text-primary text-sm font-bold hover:underline">Ver todas</button>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left">
              <thead className="bg-slate-50 text-[10px] font-bold uppercase tracking-widest text-slate-400">
                <tr>
                  <th className="px-8 py-4">Loja / Cliente</th>
                  <th className="px-8 py-4">Data adesão</th>
                  <th className="px-8 py-4">Plano</th>
                  <th className="px-8 py-4 text-right">Comissão/mês</th>
                  <th className="px-8 py-4 text-center">Status</th>
                </tr>
              </thead>
              <tbody className="text-sm font-medium">
                {[
                  { name: 'Barbearia do Zé', email: 'contato@ze.com', date: '22 Mar, 2026', plan: 'Pro', comm: 'R$ 9,90', status: 'Ativo' },
                  { name: 'Esmalteria Chic', email: 'nails@chic.com', date: '18 Mar, 2026', plan: 'Plus', comm: 'R$ 5,99', status: 'Ativo' },
                  { name: 'Dr. Fernando', email: 'fernando@med.com', date: '15 Mar, 2026', plan: 'Pro', comm: 'R$ 9,90', status: 'Ativo' },
                ].map((item, i) => (
                  <tr key={i} className="border-b border-slate-50 hover:bg-slate-50/50 transition-colors">
                    <td className="px-8 py-5">
                      <p className="font-bold">{item.name}</p>
                      <p className="text-xs text-slate-400 font-normal">{item.email}</p>
                    </td>
                    <td className="px-8 py-5 text-slate-500">{item.date}</td>
                    <td className="px-8 py-5">
                      <span className="bg-slate-100 text-slate-700 px-2 py-0.5 rounded-lg text-xs font-bold">{item.plan}</span>
                    </td>
                    <td className="px-8 py-5 text-right font-black text-primary">{item.comm}</td>
                    <td className="px-8 py-5 text-center">
                      <span className="bg-green-500/10 text-green-600 px-3 py-1 rounded-full text-xs font-bold">{item.status}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </main>
    </div>
  )
}
