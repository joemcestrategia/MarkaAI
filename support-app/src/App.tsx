import { Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider, useAuth } from './hooks/useAuth'

import ClientSupportListPage from './pages/app/support/ClientSupportListPage'
import ClientSupportNewPage from './pages/app/support/ClientSupportNewPage'
import ClientSupportDetailPage from './pages/app/support/ClientSupportDetailPage'

import SupportListPage from './pages/admin/support/SupportListPage'
import SupportDetailPage from './pages/admin/support/SupportDetailPage'
import SupportNewPage from './pages/admin/support/SupportNewPage'
import SupportReportsPage from './pages/admin/support/SupportReportsPage'
import BannersPage from './pages/admin/banners/BannersPage'
import EmailsPage from './pages/admin/emails/EmailsPage'

import LoginPage from './pages/LoginPage'

function AppRoutes() {
  const { user, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" />
      </div>
    )
  }

  if (!user) {
    return (
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    )
  }

  return (
    <Routes>
      {/* Client routes */}
      <Route path="/app/suporte" element={<ClientSupportListPage />} />
      <Route path="/app/suporte/novo" element={<ClientSupportNewPage />} />
      <Route path="/app/suporte/:id" element={<ClientSupportDetailPage />} />

      {/* Admin routes */}
      <Route path="/admin/support" element={<SupportListPage />} />
      <Route path="/admin/support/novo" element={<SupportNewPage />} />
      <Route path="/admin/support/relatorios" element={<SupportReportsPage />} />
      <Route path="/admin/support/:id" element={<SupportDetailPage />} />
      <Route path="/admin/banners" element={<BannersPage />} />
      <Route path="/admin/emails" element={<EmailsPage />} />

      {/* Default redirect */}
      <Route path="/" element={<Navigate to="/app/suporte" replace />} />
      <Route path="*" element={<Navigate to="/app/suporte" replace />} />
    </Routes>
  )
}

export default function App() {
  return (
    <AuthProvider>
      <AppRoutes />
    </AuthProvider>
  )
}
