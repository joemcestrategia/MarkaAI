import { useState, useEffect, useRef, useCallback } from 'react'
import {
  Plus, Edit2, Trash2, Eye, EyeOff, UploadCloud, X,
  Info, RefreshCw, Link2, Smartphone, ImageOff,
} from 'lucide-react'
import toast from 'react-hot-toast'
import { supabase } from '../../../lib/supabase'
import { useAuth } from '../../../hooks/useAuth'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
interface AppBanner {
  id: string
  title: string
  subtitle: string
  image_url: string
  cta_text: string
  cta_url: string
  is_active: boolean
  sort_order: number
  impressions: number
  clicks: number
  advertiser_name: string
  advertiser_email: string
  created_at: string
}


// ---------------------------------------------------------------------------
// Mobile Preview (proporção 2.5:1 — igual ao app)
// ---------------------------------------------------------------------------
function MobilePreview({
  title, subtitle, ctaText, imageUrl, imageBlob,
}: {
  title: string; subtitle: string; ctaText: string; imageUrl: string; imageBlob: string | null
}) {
  const hasImage = !!(imageBlob || imageUrl)
  return (
    <div className="relative rounded-2xl overflow-hidden w-full" style={{ height: 135 }}>
      <div className="absolute inset-0 bg-purple-900" />
      {imageBlob ? (
        <img src={imageBlob} className="absolute inset-0 w-full h-full object-cover" alt="" />
      ) : imageUrl ? (
        <img
          src={imageUrl}
          className="absolute inset-0 w-full h-full object-cover"
          alt=""
          onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
        />
      ) : null}
      <div
        className="absolute inset-0"
        style={{
          background: hasImage
            ? 'linear-gradient(135deg, rgba(106,27,154,0.82), rgba(26,0,51,0.82))'
            : 'linear-gradient(135deg, #6A1B9A, #4A0080)',
        }}
      />
      <div className="absolute bottom-3 left-3 right-3">
        <p className="text-white text-sm font-bold" style={{ textShadow: '0 2px 6px rgba(0,0,0,0.5)' }}>
          {title || 'Título do Banner'}
        </p>
        {subtitle && (
          <p className="text-white/85 text-xs mt-0.5 truncate">{subtitle}</p>
        )}
        <div className="mt-2">
          <span className="bg-white text-purple-700 text-xs font-bold px-3 py-1 rounded-full">
            {ctaText || 'Saiba mais'}
          </span>
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Form Modal
// ---------------------------------------------------------------------------
function BannerFormModal({
  existing, onClose, onSaved,
}: {
  existing: AppBanner | null; onClose: () => void; onSaved: () => void
}) {
  const [title, setTitle] = useState(existing?.title ?? 'MarkaAI')
  const [subtitle, setSubtitle] = useState(existing?.subtitle ?? '')
  const [imageUrl, setImageUrl] = useState(existing?.image_url ?? '')
  const [ctaText, setCtaText] = useState(existing?.cta_text ?? 'Saiba mais')
  const [ctaUrl, setCtaUrl] = useState(existing?.cta_url ?? 'https://markaai.com.br')
  const [sortOrder, setSortOrder] = useState(String(existing?.sort_order ?? 0))
  const [isActive, setIsActive] = useState(existing?.is_active ?? true)
  const [advertiserName, setAdvertiserName] = useState(existing?.advertiser_name ?? '')
  const [advertiserEmail, setAdvertiserEmail] = useState(existing?.advertiser_email ?? '')


  const [pickedFile, setPickedFile] = useState<File | null>(null)
  const [imageBlob, setImageBlob] = useState<string | null>(null)
  const [uploading, setUploading] = useState(false)
  const [saving, setSaving] = useState(false)

  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    if (file.size > 2 * 1024 * 1024) {
      toast.error('Arquivo muito grande. Máximo 2 MB.')
      return
    }
    setPickedFile(file)
    const reader = new FileReader()
    reader.onloadend = () => setImageBlob(reader.result as string)
    reader.readAsDataURL(file)
  }

  const clearFile = () => {
    setPickedFile(null)
    setImageBlob(null)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  const uploadImage = async (file: File): Promise<string | null> => {
    setUploading(true)
    try {
      const ext = file.name.split('.').pop()?.toLowerCase() ?? 'jpg'
      const path = `banners/${Date.now()}.${ext}`
      const { error } = await supabase.storage
        .from('app-banners')
        .upload(path, file, { contentType: file.type })
      if (error) throw error
      const { data } = supabase.storage.from('app-banners').getPublicUrl(path)
      return data.publicUrl
    } catch (err) {
      console.error(err)
      return null
    } finally {
      setUploading(false)
    }
  }

  const handleSave = async () => {
    if (!title.trim()) { toast.error('Título obrigatório'); return }
    if (!ctaText.trim()) { toast.error('Texto do botão obrigatório'); return }
    if (!ctaUrl.trim()) { toast.error('Link de destino obrigatório'); return }

    setSaving(true)
    let finalImageUrl = imageUrl.trim()

    if (pickedFile) {
      const uploaded = await uploadImage(pickedFile)
      if (!uploaded) {
        toast.error('Erro ao fazer upload da imagem. Tente novamente.')
        setSaving(false)
        return
      }
      finalImageUrl = uploaded
    }

    const payload = {
      title: title.trim(),
      subtitle: subtitle.trim(),
      image_url: finalImageUrl,
      cta_text: ctaText.trim(),
      cta_url: ctaUrl.trim(),
      sort_order: parseInt(sortOrder) || 0,
      is_active: isActive,
      advertiser_name: advertiserName.trim(),
      advertiser_email: advertiserEmail.trim(),
      updated_at: new Date().toISOString(),
    }


    const { error } = existing
      ? await supabase.from('app_banners').update(payload).eq('id', existing.id)
      : await supabase.from('app_banners').insert(payload)

    if (error) {
      toast.error('Erro ao salvar: ' + error.message)
    } else {
      toast.success(existing ? 'Banner atualizado!' : 'Banner criado!')
      onSaved()
    }
    setSaving(false)
  }

  const isBusy = saving || uploading

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-xl max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-5 pb-4 border-b border-gray-100">
          <h2 className="text-lg font-bold text-gray-900">
            {existing ? 'Editar Banner' : 'Novo Banner'}
          </h2>
          <button onClick={onClose} className="p-1 rounded-full hover:bg-gray-100 transition">
            <X size={18} className="text-gray-500" />
          </button>
        </div>

        <div className="px-6 py-5 space-y-5">
          {/* Preview ao vivo */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <span className="flex items-center gap-1.5 text-xs text-gray-500">
                <Smartphone size={13} /> Preview mobile (tamanho real)
              </span>
              <span className="text-xs text-amber-600 bg-amber-50 border border-amber-200 px-2 py-0.5 rounded-full">
                1080 × 432 px recomendado
              </span>
            </div>
            <MobilePreview
              title={title} subtitle={subtitle} ctaText={ctaText}
              imageUrl={imageUrl} imageBlob={imageBlob}
            />
          </div>

          {/* Seção de imagem */}
          <div className="space-y-3">
            <p className="text-sm font-semibold text-gray-700">Imagem do Banner</p>
            {/* Guia */}
            <div className="flex gap-2 bg-blue-50 border border-blue-200 rounded-lg px-3 py-2">
              <Info size={15} className="text-blue-500 shrink-0 mt-0.5" />
              <p className="text-xs text-gray-700">
                Tamanho ideal: <strong>1080 × 432 px</strong> · Proporção 2.5:1
                <br />Formatos: JPG, PNG, WebP · Máximo: 2 MB
              </p>
            </div>
            {/* Arquivo escolhido */}
            {pickedFile ? (
              <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-lg px-3 py-2">
                <span className="text-green-600 text-xs truncate flex-1">{pickedFile.name}</span>
                <button onClick={clearFile} className="text-green-500 hover:text-green-700">
                  <X size={14} />
                </button>
              </div>
            ) : (
              <button
                onClick={() => fileInputRef.current?.click()}
                className="w-full flex items-center justify-center gap-2 border-2 border-dashed border-purple-300 rounded-xl py-3 text-sm text-purple-600 hover:bg-purple-50 transition"
              >
                <UploadCloud size={18} />
                Escolher Imagem do Dispositivo
              </button>
            )}
            <input
              ref={fileInputRef}
              type="file"
              accept="image/jpeg,image/jpg,image/png,image/webp"
              className="hidden"
              onChange={handleFileChange}
            />
            {/* URL alternativa */}
            <div>
              <label className="text-xs text-gray-500 mb-1 block">ou cole uma URL de imagem</label>
              <div className="flex items-center gap-2 border border-gray-300 rounded-lg px-3">
                <Link2 size={14} className="text-gray-400 shrink-0" />
                <input
                  type="url"
                  value={imageUrl}
                  onChange={(e) => setImageUrl(e.target.value)}
                  placeholder="https://..."
                  className="flex-1 text-sm py-2 outline-none"
                />
              </div>
              {pickedFile && (
                <p className="text-xs text-amber-500 mt-1">O arquivo acima terá prioridade sobre a URL</p>
              )}
            </div>
          </div>

          <hr className="border-gray-100" />

          {/* Campos de texto */}
          <div className="space-y-3">
            <Field label="Título *" value={title} onChange={setTitle} placeholder="Ex: Promoção de Inverno" />
            <Field label="Subtítulo" value={subtitle} onChange={setSubtitle} placeholder="Ex: 20% de desconto em todos os serviços" />
            <Field label="Texto do botão *" value={ctaText} onChange={setCtaText} placeholder="Ex: Ver oferta" />
            <Field label="Link ao clicar no banner *" value={ctaUrl} onChange={setCtaUrl} placeholder="https://..." type="url" />
            <Field label="Ordem de exibição" value={sortOrder} onChange={setSortOrder} placeholder="0" type="number" />
          </div>

          {/* Anunciante */}
          <div className="bg-purple-50 border border-purple-200 rounded-xl p-4 space-y-3">
            <p className="text-xs font-semibold text-purple-700 flex items-center gap-1.5">
              <span>🏢</span> Dados do Anunciante (opcional)
            </p>
            <Field label="Nome da empresa" value={advertiserName} onChange={setAdvertiserName} placeholder="Ex: Beleza Total" />
            <Field label="E-mail do anunciante" value={advertiserEmail} onChange={setAdvertiserEmail} placeholder="contato@empresa.com" type="email" />
          </div>

          {/* Toggle ativo */}
          <div className="flex items-center justify-between bg-gray-50 rounded-xl px-4 py-3">
            <span className="text-sm font-medium text-gray-700">Banner ativo</span>
            <button
              onClick={() => setIsActive(v => !v)}
              className={`w-12 h-6 rounded-full transition-colors ${isActive ? 'bg-purple-600' : 'bg-gray-300'}`}
            >
              <div className={`w-5 h-5 bg-white rounded-full shadow mx-0.5 transition-transform ${isActive ? 'translate-x-6' : 'translate-x-0'}`} />
            </button>
          </div>
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-3 px-6 py-4 border-t border-gray-100">
          <button
            onClick={onClose}
            disabled={isBusy}
            className="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50 transition disabled:opacity-50"
          >
            Cancelar
          </button>
          <button
            onClick={handleSave}
            disabled={isBusy}
            className="flex items-center gap-2 px-5 py-2 bg-purple-600 text-white text-sm font-medium rounded-lg hover:bg-purple-700 transition disabled:opacity-50"
          >
            {isBusy && <span className="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin" />}
            {uploading ? 'Enviando...' : saving ? 'Salvando...' : 'Salvar'}
          </button>
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Field helper
// ---------------------------------------------------------------------------
function Field({
  label, value, onChange, placeholder, type = 'text',
}: {
  label: string; value: string; onChange: (v: string) => void; placeholder?: string; type?: string
}) {
  return (
    <div>
      <label className="text-xs text-gray-500 mb-1 block">{label}</label>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-purple-300"
      />
    </div>
  )
}

// ---------------------------------------------------------------------------
// Banner Card na lista
// ---------------------------------------------------------------------------
function BannerCard({
  banner, onEdit, onDelete, onToggleActive,
}: {
  banner: AppBanner
  onEdit: () => void
  onDelete: () => void
  onToggleActive: () => void
}) {
  const ctr = banner.impressions > 0
    ? ((banner.clicks / banner.impressions) * 100).toFixed(1)
    : '0.0'

  return (
    <div className={`bg-white rounded-2xl shadow-sm border overflow-hidden transition ${
      banner.is_active ? 'border-gray-100' : 'border-orange-200 opacity-70'
    }`}>
      {/* Preview mobile */}
      <div className="relative" style={{ height: 135 }}>
        <div className="absolute inset-0 bg-purple-900" />
        {banner.image_url && (
          <img
            src={banner.image_url}
            className="absolute inset-0 w-full h-full object-cover"
            alt=""
            onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
          />
        )}
        <div
          className="absolute inset-0"
          style={{
            background: banner.image_url
              ? 'linear-gradient(135deg, rgba(106,27,154,0.75), rgba(26,0,51,0.75))'
              : 'linear-gradient(135deg, #6A1B9A, #4A0080)',
          }}
        />
        <div className="absolute bottom-3 left-3 right-3">
          <p className="text-white text-sm font-bold truncate" style={{ textShadow: '0 2px 6px rgba(0,0,0,0.5)' }}>
            {banner.title}
          </p>
          {banner.subtitle && (
            <p className="text-white/85 text-xs mt-0.5 truncate">{banner.subtitle}</p>
          )}
          <div className="mt-2">
            <span className="bg-white text-purple-700 text-xs font-bold px-3 py-1 rounded-full">{banner.cta_text}</span>
          </div>
        </div>
        {/* Status badge */}
        <div className="absolute top-2.5 right-2.5">
          <span className={`text-xs font-bold px-2.5 py-1 rounded-full ${
            banner.is_active ? 'bg-green-500 text-white' : 'bg-orange-500 text-white'
          }`}>
            {banner.is_active ? 'Ativo' : 'Arquivado'}
          </span>
        </div>
        <div className="absolute top-2.5 left-2.5 flex items-center gap-1">
          <Smartphone size={11} className="text-white/70" />
          <span className="text-white/70 text-xs">Preview</span>
        </div>
      </div>

      {/* Métricas */}
      <div className="bg-gray-50 px-4 py-2 flex items-center gap-4 text-xs">
        <div className="flex flex-col items-center">
          <span className="font-bold text-blue-700 text-sm">{banner.impressions.toLocaleString()}</span>
          <span className="text-gray-400">Impressões</span>
        </div>
        <div className="flex flex-col items-center">
          <span className="font-bold text-purple-700 text-sm">{banner.clicks.toLocaleString()}</span>
          <span className="text-gray-400">Cliques</span>
        </div>
        <div className="flex flex-col items-center">
          <span className="font-bold text-teal-700 text-sm">{ctr}%</span>
          <span className="text-gray-400">CTR</span>
        </div>
        {banner.advertiser_name && (
          <div className="ml-auto flex items-center gap-1 text-gray-500">
            <span>🏢</span>
            <span className="truncate max-w-[80px]">{banner.advertiser_name}</span>
          </div>
        )}
      </div>

      {/* Detalhes e ações */}
      <div className="px-4 py-3">
        <div className="flex items-center gap-1.5 text-xs text-gray-500 truncate mb-3">
          <Link2 size={12} className="shrink-0" />
          <span className="truncate">{banner.cta_url}</span>
          <span className="ml-auto shrink-0">Ordem: {banner.sort_order}</span>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={onToggleActive}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs border rounded-lg transition ${
              banner.is_active
                ? 'border-orange-300 text-orange-700 hover:bg-orange-50'
                : 'border-green-300 text-green-700 hover:bg-green-50'
            }`}
          >
            {banner.is_active ? <EyeOff size={13} /> : <Eye size={13} />}
            {banner.is_active ? 'Arquivar' : 'Reativar'}
          </button>
          <button
            onClick={onEdit}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs border border-gray-300 rounded-lg text-gray-600 hover:bg-gray-50 transition"
          >
            <Edit2 size={13} /> Editar
          </button>
          <button
            onClick={onDelete}
            className="ml-auto p-1.5 text-red-300 hover:text-red-600 hover:bg-red-50 rounded-lg transition"
            title="Excluir permanentemente"
          >
            <Trash2 size={14} />
          </button>
        </div>
      </div>
    </div>
  )
}


// ---------------------------------------------------------------------------
// Main Page
// ---------------------------------------------------------------------------

export default function BannersPage() {
  const { isAdmin } = useAuth()
  const [banners, setBanners] = useState<AppBanner[]>([])
  const [loading, setLoading] = useState(true)
  const [formOpen, setFormOpen] = useState(false)
  const [editBanner, setEditBanner] = useState<AppBanner | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<AppBanner | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('app_banners')
      .select('*')
      .order('sort_order', { ascending: true })
    if (error) toast.error('Erro ao carregar banners: ' + error.message)
    else setBanners(data ?? [])
    setLoading(false)
  }, [])

  useEffect(() => { load() }, [load])

  const handleToggleActive = async (banner: AppBanner) => {
    const { error } = await supabase
      .from('app_banners')
      .update({ is_active: !banner.is_active })
      .eq('id', banner.id)
    if (error) toast.error('Erro ao atualizar.')
    else {
      toast.success(banner.is_active ? 'Banner arquivado.' : 'Banner reativado!')
      load()
    }
  }

  const handlePermanentDelete = async (banner: AppBanner) => {
    const { error } = await supabase.from('app_banners').delete().eq('id', banner.id)
    if (error) toast.error('Erro ao excluir.')
    else { toast.success('Banner excluído permanentemente.'); setDeleteTarget(null); load() }
  }


  const openNew = () => { setEditBanner(null); setFormOpen(true) }
  const openEdit = (b: AppBanner) => { setEditBanner(b); setFormOpen(true) }

  if (!isAdmin) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-red-500 font-medium">Acesso restrito a administradores.</p>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-4xl mx-auto px-4 py-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Banners de Marketing</h1>
            <p className="text-sm text-gray-500 mt-0.5">
              Aparecem no carousel da tela inicial do app, junto às lojas em destaque
            </p>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={load}
              className="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition"
            >
              <RefreshCw size={16} />
            </button>
            <button
              onClick={openNew}
              className="flex items-center gap-2 px-4 py-2 bg-purple-600 text-white text-sm font-medium rounded-lg hover:bg-purple-700 transition"
            >
              <Plus size={16} /> Novo Banner
            </button>
          </div>
        </div>

        {/* Guia de dimensões */}
        <div className="flex items-start gap-3 bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 mb-6">
          <Info size={16} className="text-amber-500 shrink-0 mt-0.5" />
          <div className="text-sm text-amber-800">
            <strong>Dimensões para o app mobile:</strong> 1080 × 432 px (proporção 2.5:1) ·
            Formatos JPG, PNG ou WebP · Máximo 2 MB.
            O app sobrepõe um gradiente roxo + título/subtítulo/botão — use a imagem como fundo visual.
          </div>
        </div>

        {/* Content */}
        {loading ? (
          <div className="flex items-center justify-center h-48">
            <div className="w-8 h-8 border-2 border-purple-600 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : banners.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-48 text-gray-400 gap-3">
            <ImageOff size={48} className="opacity-50" />
            <p className="text-sm">Nenhum banner cadastrado.</p>
            <button onClick={openNew} className="text-sm text-purple-600 underline">Criar o primeiro banner</button>
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {banners.map((b) => (
              <BannerCard
                key={b.id}
                banner={b}
                onEdit={() => openEdit(b)}
                onDelete={() => setDeleteTarget(b)}
                onToggleActive={() => handleToggleActive(b)}
              />
            ))}
          </div>
        )}
      </div>

      {/* Form modal */}
      {formOpen && (
        <BannerFormModal
          existing={editBanner}
          onClose={() => setFormOpen(false)}
          onSaved={() => { setFormOpen(false); load() }}
        />
      )}

      {/* Delete confirm modal */}
      {deleteTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="bg-white rounded-2xl shadow-xl p-6 max-w-sm w-full">
            <h3 className="text-lg font-bold text-gray-900 mb-2">Excluir banner?</h3>
            <p className="text-sm text-gray-500 mb-5">
              O banner <strong>"{deleteTarget.title}"</strong> será removido permanentemente.
            </p>
            <div className="flex justify-end gap-3">
              <button
                onClick={() => setDeleteTarget(null)}
                className="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50"
              >
                Cancelar
              </button>
              <button
                onClick={() => handlePermanentDelete(deleteTarget)}
                className="px-4 py-2 bg-red-700 text-white text-sm font-medium rounded-lg hover:bg-red-800"
              >
                Excluir permanentemente
              </button>

            </div>
          </div>
        </div>
      )}
    </div>
  )
}
