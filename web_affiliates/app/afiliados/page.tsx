'use client'

import React, { useState } from 'react'
import { Rocket, Target, DollarSign, ArrowRight, CheckCircle2, Calculator, Info } from 'lucide-react'

export default function AffiliatePublicPage() {
  const [indicacoes, setIndicacoes] = useState(5)
  const [model, setModel] = useState<'recurring' | 'one_time'>('recurring')

  const commission = model === 'recurring' ? 10 : 30
  const avgSubscription = 59.90
  const monthlyEarnings = indicacoes * avgSubscription * (commission / 100)

  return (
    <div className="min-h-screen bg-slate-50 font-sans text-slate-900">
      {/* Header */}
      <nav className="flex items-center justify-between px-6 py-4 bg-white border-b sticky top-0 z-50">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 bg-primary rounded-lg flex items-center justify-center text-white font-bold">M</div>
          <span className="text-xl font-bold tracking-tight">MarkaAI <span className="text-primary">Afiliados</span></span>
        </div>
        <div className="flex items-center gap-4">
          <button className="text-slate-600 font-medium hover:text-primary transition-colors">Entrar</button>
          <button className="bg-primary text-white px-5 py-2 rounded-full font-semibold hover:bg-primary-dark transition-all shadow-md shadow-primary/20">
            Quero ser afiliado
          </button>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="relative py-20 px-6 overflow-hidden">
        <div className="max-w-6xl mx-auto flex flex-col md:flex-row items-center gap-12">
          <div className="flex-1 space-y-6 text-center md:text-left">
            <h1 className="text-4xl md:text-6xl font-extrabold leading-tight text-slate-900">
              Indique o MarkaAI e ganhe <span className="text-transparent bg-clip-text bg-gradient-to-r from-primary to-purple-400">comissão recorrente</span>
            </h1>
            <p className="text-xl text-slate-600 max-w-2xl mx-auto md:mx-0">
              Você indica, a loja assina, você recebe automaticamente. Transforme sua rede em uma fonte de renda passiva previsível.
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center md:justify-start pt-4">
              <button className="bg-primary text-white px-8 py-4 rounded-xl text-lg font-bold hover:bg-primary-dark transition-all shadow-lg hover:translate-y--1">
                Começar agora o Programa
              </button>
              <button className="bg-white text-slate-700 border-2 border-slate-200 px-8 py-4 rounded-xl text-lg font-bold hover:border-primary transition-all">
                Ver como funciona
              </button>
            </div>
          </div>
          <div className="flex-1 relative">
            <div className="absolute -inset-4 bg-primary/10 blur-3xl rounded-full"></div>
            <div className="bg-white p-8 rounded-3xl shadow-2xl relative border border-slate-100">
               <div className="space-y-4">
                 <div className="flex items-center justify-between p-4 bg-slate-50 rounded-2xl border border-slate-100">
                   <div className="flex items-center gap-3">
                     <div className="w-10 h-10 bg-green-100 text-green-600 rounded-full flex items-center justify-center">
                       <DollarSign size={20} />
                     </div>
                     <div>
                       <p className="text-xs text-slate-400 font-medium">Comissão recebida</p>
                       <p className="font-bold">R$ 149,90</p>
                     </div>
                   </div>
                   <span className="text-xs bg-green-500/10 text-green-600 px-2 py-1 rounded-full font-bold">PAGO</span>
                 </div>
                 <div className="flex items-center gap-3 p-4 bg-primary/5 rounded-2xl border border-primary/10">
                    <div className="w-10 h-10 bg-primary text-white rounded-full flex items-center justify-center">
                      <Target size={20} />
                    </div>
                    <div>
                      <p className="text-xs text-primary/60 font-medium">Novo Referral</p>
                      <p className="font-bold">Barbearia Elite</p>
                    </div>
                 </div>
                 <div className="pt-2 text-center">
                   <p className="text-sm text-slate-500 font-medium">Seu cupom: <span className="text-primary font-bold">MARKA10</span></p>
                 </div>
               </div>
            </div>
          </div>
        </div>
      </section>

      {/* Como Funciona */}
      <section className="py-24 bg-white px-6">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16 space-y-4">
            <h2 className="text-3xl md:text-4xl font-bold">Ganhos em 3 passos simples</h2>
            <p className="text-slate-500 max-w-xl mx-auto">Tudo o que você precisa fazer é indicar, o resto a gente cuida.</p>
          </div>
          <div className="grid md:grid-cols-3 gap-12">
            {[
              { icon: <Target className="text-blue-500" />, title: 'Cadastre-se', desc: 'Receba seu cupom exclusivo em segundos após aprovação rápida.' },
              { icon: <Rocket className="text-purple-500" />, title: 'Indique Lojistas', desc: 'Eles ganham 15% de desconto no 1º mês e você ganha sua comissão.' },
              { icon: <DollarSign className="text-green-500" />, title: 'Receba via Stripe', desc: 'Transferência automática para sua conta conectada a cada pagamento.' },
            ].map((step, i) => (
              <div key={i} className="space-y-4 text-center group">
                <div className="w-20 h-20 bg-slate-50 rounded-3xl flex items-center justify-center mx-auto group-hover:bg-primary/5 transition-colors border border-slate-100">
                  {step.icon}
                </div>
                <h3 className="text-xl font-bold">{i+1}. {step.title}</h3>
                <p className="text-slate-500 leading-relaxed">{step.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Escolha seu Modelo */}
      <section className="py-24 px-6 relative overflow-hidden">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold">Escolha como quer ganhar</h2>
          </div>
          <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            <div className={`p-8 rounded-3xl border-2 transition-all cursor-pointer ${model === 'recurring' ? 'border-primary bg-white shadow-xl ring-4 ring-primary/5' : 'border-slate-200 bg-slate-50'}`}
                 onClick={() => setModel('recurring')}>
              <div className="flex justify-between items-start mb-6">
                <div className={`w-12 h-12 rounded-2xl flex items-center justify-center ${model === 'recurring' ? 'bg-primary text-white' : 'bg-slate-200 text-slate-500'}`}>
                  <Rocket size={24} />
                </div>
                {model === 'recurring' && <CheckCircle2 className="text-primary" />}
              </div>
              <h3 className="text-2xl font-bold mb-2">Comissão Recorrente</h3>
              <p className="text-3xl font-black text-primary mb-4">10% <span className="text-lg font-normal text-slate-500">/ mês</span></p>
              <ul className="space-y-3 mb-8">
                <li className="flex items-center gap-2 text-sm text-slate-600 font-medium"><CheckCircle2 size={16} className="text-green-500" /> Renda passiva previsível</li>
                <li className="flex items-center gap-2 text-sm text-slate-600 font-medium"><CheckCircle2 size={16} className="text-green-500" /> Ganhe enquanto o cliente assinar</li>
              </ul>
            </div>

            <div className={`p-8 rounded-3xl border-2 transition-all cursor-pointer ${model === 'one_time' ? 'border-primary bg-white shadow-xl ring-4 ring-primary/5' : 'border-slate-200 bg-slate-50'}`}
                 onClick={() => setModel('one_time')}>
              <div className="flex justify-between items-start mb-6">
                <div className={`w-12 h-12 rounded-2xl flex items-center justify-center ${model === 'one_time' ? 'bg-primary text-white' : 'bg-slate-200 text-slate-500'}`}>
                  <DollarSign size={24} />
                </div>
                {model === 'one_time' && <CheckCircle2 className="text-primary" />}
              </div>
              <h3 className="text-2xl font-bold mb-2">Comissão Única</h3>
              <p className="text-3xl font-black text-primary mb-4">30% <span className="text-lg font-normal text-slate-500">no 1º mês</span></p>
              <ul className="space-y-3 mb-8">
                <li className="flex items-center gap-2 text-sm text-slate-600 font-medium"><CheckCircle2 size={16} className="text-green-500" /> Valor maior de imediato</li>
                <li className="flex items-center gap-2 text-sm text-slate-600 font-medium"><CheckCircle2 size={16} className="text-green-500" /> Ideal para vendas rápidas</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Calculator */}
      <section className="py-24 bg-slate-900 text-white px-6">
        <div className="max-w-4xl mx-auto bg-slate-800 p-8 md:p-12 rounded-[2rem] border border-slate-700 shadow-2xl">
          <div className="flex flex-col md:flex-row gap-12 items-center">
            <div className="flex-1 space-y-8 w-full">
              <div className="flex items-center gap-3">
                <Calculator className="text-primary" />
                <h2 className="text-2xl font-bold">Simulador de ganhos</h2>
              </div>
              <div className="space-y-6">
                <div>
                  <div className="flex justify-between mb-4">
                    <label className="font-semibold">Indicações por mês</label>
                    <span className="text-primary font-bold">{indicacoes} lojas</span>
                  </div>
                  <input type="range" min="1" max="50" step="1" value={indicacoes} onChange={(e: React.ChangeEvent<HTMLInputElement>) => setIndicacoes(parseInt(e.target.value))}
                    className="w-full h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-primary" />
                </div>
                <div className="flex gap-4 p-1 bg-slate-700 rounded-xl">
                   <button onClick={() => setModel('recurring')} className={`flex-1 py-3 rounded-lg font-bold transition-all ${model === 'recurring' ? 'bg-primary shadow-lg' : 'hover:bg-slate-600 text-slate-400'}`}>Recorrente</button>
                   <button onClick={() => setModel('one_time')} className={`flex-1 py-3 rounded-lg font-bold transition-all ${model === 'one_time' ? 'bg-primary shadow-lg' : 'hover:bg-slate-600 text-slate-400'}`}>Única</button>
                </div>
              </div>
            </div>
            <div className="flex-1 text-center space-y-2">
              <p className="text-slate-400 font-medium">Estimativa de ganhos extras</p>
              <p className="text-5xl md:text-7xl font-black text-transparent bg-clip-text bg-gradient-to-r from-primary to-purple-400">
                R$ {monthlyEarnings.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
              </p>
              <p className="text-slate-400">{model === 'recurring' ? 'Por mês (acumulado)' : 'No total imediato'}</p>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-24 px-6 bg-white">
        <div className="max-w-4xl mx-auto space-y-12">
          <h2 className="text-3xl font-bold text-center">Perguntas Frequentes</h2>
          <div className="grid gap-6">
            {[
              { q: 'Quanto custa para participar?', a: 'Nada! O Programa de Afiliados MarkaAI é totalmente gratuito.' },
              { q: 'Quando recebo meus pagamentos?', a: 'Assim que o lojista indicado realiza o pagamento e a Stripe processa a transação, sua comissão cai automaticamente na sua conta Stripe Connect.' },
              { q: 'Sou lojista, posso indicar?', a: 'Com certeza! Lojistas, agências, consultores ou qualquer usuário MarkaAI pode se tonar afiliado.' },
            ].map((item, i) => (
              <div key={i} className="p-6 rounded-2xl border border-slate-100 bg-slate-50 space-y-2">
                <h4 className="font-bold flex items-center gap-2"><Info size={18} className="text-primary" /> {item.q}</h4>
                <p className="text-slate-600 leading-relaxed">{item.a}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA Final */}
      <section className="py-24 px-6 bg-gradient-to-b from-slate-50 to-white text-center">
        <div className="max-w-xl mx-auto space-y-8">
           <h2 className="text-4xl font-black">Pronto para começar?</h2>
           <p className="text-xl text-slate-600 leading-relaxed">Junte-se a centenas de parceiros e comece a faturar hoje mesmo com o melhor agendador inteligente do Brasil.</p>
           <button className="bg-primary hover:bg-primary-dark text-white text-xl font-bold px-12 py-5 rounded-2xl shadow-xl shadow-primary/20 transition-all hover:-translate-y-1 w-full sm:w-auto">
             Fazer meu cadastro gratuito
           </button>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-12 px-6 border-t text-slate-500 text-sm">
        <div className="max-w-6xl mx-auto flex flex-col md:flex-row justify-between items-center gap-8">
           <div className="flex items-center gap-2 grayscale brightness-50">
            <div className="w-6 h-6 bg-slate-600 rounded flex items-center justify-center text-white font-bold text-xs">M</div>
            <span className="font-bold tracking-tight">MarkaAI</span>
          </div>
          <div className="flex gap-8">
            <a href="#" className="hover:text-primary transition-colors">Termos do Programa</a>
            <a href="#" className="hover:text-primary transition-colors">Política de Privacidade</a>
            <a href="#" className="hover:text-primary transition-colors">Suporte</a>
          </div>
          <p>© 2026 MarkaAI. Todos os direitos reservados.</p>
        </div>
      </footer>
    </div>
  )
}
