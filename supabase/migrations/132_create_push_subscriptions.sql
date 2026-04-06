-- Tabela para armazenar subscriptions de Web Push (PWA)
CREATE TABLE IF NOT EXISTS "public"."push_subscriptions" (
  "id"         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  "user_id"    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  "endpoint"   text        NOT NULL,
  "p256dh"     text        NOT NULL,
  "auth_key"   text        NOT NULL,
  "user_agent" text,
  "created_at" timestamptz DEFAULT now(),
  "updated_at" timestamptz DEFAULT now(),
  UNIQUE("user_id", "endpoint")
);

ALTER TABLE "public"."push_subscriptions" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own push subscriptions"
  ON "public"."push_subscriptions"
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Índice para busca por user_id (envio de push por usuário)
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id
  ON "public"."push_subscriptions" (user_id);
