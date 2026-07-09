create table app_versions (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'android',
  version_name text not null,        -- ex: '1.4.0'
  version_code int not null,         -- ex: 14, deve bater com o build number do pubspec.yaml
  apk_url text not null,             -- URL do asset no GitHub Release
  changelog text,
  force_update boolean not null default false,
  created_at timestamptz not null default now()
);

-- Leitura pública (qualquer usuário do app precisa checar, mesmo sem login)
alter table app_versions enable row level security;

create policy "app_versions_select_public"
  on app_versions for select
  using (true);

-- Nenhuma policy de insert/update/delete para authenticated/anon.
-- Inserções só devem acontecer via service_role (script de release), nunca pelo app.
