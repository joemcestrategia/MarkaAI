#!/bin/bash
set -e

# As chaves do Supabase foram removidas por segurança.
# O script agora gerará o código SQL para você rodar manualmente no painel.

# Confirmar se o gh CLI está autenticado
if ! gh auth status >/dev/null 2>&1; then
    echo "Erro: O GitHub CLI (gh) não está autenticado. Rode 'gh auth login' primeiro."
    exit 1
fi

# Parâmetros
changelog=""
force_update="false"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--changelog) changelog="$2"; shift ;;
        -f|--force) force_update="true" ;;
        *) echo "Parâmetro desconhecido: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$changelog" ]; then
    read -p "Digite o changelog para esta versão: " changelog
fi

if [ "$force_update" == "false" ]; then
    read -p "Forçar atualização para os usuários? (s/N): " force_response
    if [[ "$force_response" =~ ^[Ss] ]]; then
        force_update="true"
    fi
fi

# Ler version do pubspec.yaml
VERSION_LINE=$(grep '^version:' pubspec.yaml)
# Ex: version: 1.4.0+14
VERSION_STR=$(echo "$VERSION_LINE" | awk '{print $2}')
VERSION_NAME=$(echo "$VERSION_STR" | cut -d'+' -f1)
VERSION_CODE=$(echo "$VERSION_STR" | cut -d'+' -f2)

if [ -z "$VERSION_NAME" ] || [ -z "$VERSION_CODE" ]; then
    echo "Erro: Não foi possível extrair a versão do pubspec.yaml ($VERSION_STR)"
    exit 1
fi

echo "Versão detectada: $VERSION_NAME (Build: $VERSION_CODE)"

echo "Construindo APK (release)..."
# flutter build apk --release

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_PATH" ]; then
    echo "Erro: APK não encontrado em $APK_PATH"
    exit 1
fi

TAG_NAME="v${VERSION_NAME}+${VERSION_CODE}"

echo ""
echo "=== RESUMO DO RELEASE ==="
echo "Versão: $VERSION_NAME"
echo "Build Code: $VERSION_CODE"
echo "Changelog: $changelog"
echo "Forçar Atualização: $force_update"
echo "APK: $APK_PATH"
echo "Tag: $TAG_NAME"
echo "========================="

read -p "Confirma a publicação desta versão? (s/N): " confirm_pub
if [[ ! "$confirm_pub" =~ ^[Ss] ]]; then
    echo "Publicação cancelada."
    exit 0
fi

echo "Criando e enviando tag $TAG_NAME..."
git tag "$TAG_NAME"
git push origin "$TAG_NAME"

echo "Criando GitHub Release e fazendo upload do APK..."
gh release create "$TAG_NAME" "$APK_PATH" --title "Release $VERSION_NAME (Android)" --notes "$changelog"

echo "Recuperando URL pública do APK..."
# O comando retorna um JSON, usamos jq interno do gh para pegar a URL do asset
APK_URL=$(gh release view "$TAG_NAME" --json assets --jq '.assets[0].url')

if [ -z "$APK_URL" ] || [ "$APK_URL" == "null" ]; then
    # Fallback se falhar ao processar JSON
    REPO_URL=$(gh repo view --json url --jq '.url')
    APK_URL="${REPO_URL}/releases/download/${TAG_NAME}/app-release.apk"
fi

echo ""
echo "✅ Release $VERSION_NAME publicado no GitHub com sucesso!"
echo "URL do APK: $APK_URL"
echo ""
echo "⚠️  Para liberar a atualização para os usuários, copie e cole o comando SQL abaixo no SQL Editor do Supabase:"
echo "------------------------------------------------------------------------------------------------"
echo "INSERT INTO app_versions (platform, version_name, version_code, apk_url, changelog, force_update)"
echo "VALUES ('android', '$VERSION_NAME', $VERSION_CODE, '$APK_URL', '$changelog', $force_update);"
echo "------------------------------------------------------------------------------------------------"
echo ""
