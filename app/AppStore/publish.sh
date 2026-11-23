#!/bin/bash
# Publishes PadDeck step by step. Asks before anything that can't be undone.
#   ./app/AppStore/publish.sh            (run from anywhere inside the repo)
# Output is also saved in app/AppStore/publish.log.
#
# Steps:
#   1. compiles the iOS app (simulator) to check the build
#   2. merges app-store-release into main and turns on GitHub Pages (docs/)
#   3. signs, notarizes and releases PadDeck for Mac (v1.2)
#   4. archives the iOS app and uploads it to App Store Connect
# What stays manual (App Store Connect website): agreements, screenshots, texts, price, submit.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/app/AppStore/publish.log"
exec > >(tee "$LOG") 2>&1

REPO=douugr/paddeck
BRANCH=app-store-release
MAC_VERSION=1.2
PROFILE="${NOTARY_PROFILE:-paddeck-notary}"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*"; exit 1; }
ask()  { local a; read -r -p "$1 [s/N] " a </dev/tty; [[ "$a" =~ ^[sSyY] ]]; }

# --- 0. Tools -------------------------------------------------------------------
step "Conferindo ferramentas"
for t in git xcodebuild gh; do command -v $t >/dev/null || fail "falta '$t'"; done
command -v xcodegen >/dev/null || { echo "Instalando xcodegen…"; brew install xcodegen || fail "instale com: brew install xcodegen"; }
gh auth status >/dev/null 2>&1 || fail "rode 'gh auth login' antes"
ok "git, xcodebuild, gh e xcodegen"

step "Atualizando o branch $BRANCH"
git fetch -q origin || fail "git fetch falhou"
git switch -q "$BRANCH" 2>/dev/null || git switch -q -c "$BRANCH" --track "origin/$BRANCH" || fail "não consegui trocar para $BRANCH (há alterações locais?)"
git pull -q --ff-only || fail "git pull falhou"
ok "$(git log --oneline -1)"

# --- Team ID --------------------------------------------------------------------
TEAM="${TEAM_ID:-$(grep -E '^\s*DEVELOPMENT_TEAM:' app/project.yml | head -1 | sed -E 's/.*: *"?([A-Z0-9]*)"?.*/\1/')}"
if [[ -z "$TEAM" ]]; then
  echo "Seu Team ID fica em developer.apple.com › Membership (10 caracteres, ex.: AB12CD34EF)."
  read -r -p "Team ID: " TEAM </dev/tty
fi
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail "Team ID inválido: '$TEAM'"
sed -i '' -E "s/^( *DEVELOPMENT_TEAM:).*/\1 \"$TEAM\"          # your Apple Developer Team ID/" app/project.yml
ok "Team ID $TEAM"

# --- 1. Build check -------------------------------------------------------------
step "1/4 Compilando o app para o simulador"
(cd app && xcodegen -q) || fail "xcodegen falhou"
if xcodebuild -project app/PadDeck.xcodeproj -scheme PadDeck -configuration Debug \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath app/build/DerivedData \
     CODE_SIGNING_ALLOWED=NO build -quiet; then
  ok "o app compila"
else
  fail "a compilação falhou: os erros estão em app/AppStore/publish.log"
fi

# --- 2. Merge + GitHub Pages ----------------------------------------------------
step "2/4 Juntar no main e publicar o site"
if ask "Juntar $BRANCH no main, enviar para o GitHub e ligar o GitHub Pages (docs/)?"; then
  git add app/project.yml && git commit -q -m "Set the development team" || true
  git push -q origin "$BRANCH"
  git switch -q main && git pull -q --ff-only && git merge -q --no-edit "$BRANCH" && git push -q origin main \
    || fail "o merge no main falhou"
  ok "main atualizado"
  if gh api "repos/$REPO/pages" >/dev/null 2>&1; then
    gh api -X PUT "repos/$REPO/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null && ok "GitHub Pages já estava ligado (fonte: main /docs)"
  else
    gh api -X POST "repos/$REPO/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null \
      && ok "GitHub Pages ligado: https://douugr.github.io/paddeck/ (pode levar alguns minutos)" \
      || echo "Não consegui ligar o Pages pela API: ligue em Settings › Pages › main /docs."
  fi
  git switch -q "$BRANCH"
else
  echo "Pulado."
fi

# --- 3. Mac app: notarize + release ---------------------------------------------
step "3/4 PadDeck para Mac $MAC_VERSION (assinado e notarizado)"
if ask "Assinar com o Developer ID, notarizar e publicar o release v$MAC_VERSION?"; then
  if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "Falta o certificado 'Developer ID Application'."
    echo "Crie em: Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application"
    read -r -p "Pressione Enter quando tiver criado… " _ </dev/tty
    security find-identity -v -p codesigning | grep -q "Developer ID Application" || fail "certificado não encontrado"
  fi
  if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "Primeira notarização: vou guardar suas credenciais no Keychain (perfil '$PROFILE')."
    echo "Você vai precisar de uma senha de app: account.apple.com › Login e Segurança › Senhas de app."
    read -r -p "Apple ID (e-mail): " APPLE_ID </dev/tty
    xcrun notarytool store-credentials "$PROFILE" --apple-id "$APPLE_ID" --team-id "$TEAM" </dev/tty \
      || fail "não consegui guardar as credenciais"
  fi
  ./mac-agent/build.sh notarize || fail "a notarização falhou (detalhes acima)"
  if gh release view "v$MAC_VERSION" -R "$REPO" >/dev/null 2>&1; then
    gh release upload "v$MAC_VERSION" mac-agent/build/PadDeck-mac.zip -R "$REPO" --clobber && ok "zip do release v$MAC_VERSION atualizado"
  else
    gh release create "v$MAC_VERSION" mac-agent/build/PadDeck-mac.zip -R "$REPO" --target main \
      -t "PadDeck $MAC_VERSION for Mac" \
      -n "Signed with Developer ID and notarized by Apple. English menu (Portuguese on Macs set to Portuguese). Download PadDeck-mac.zip, unzip it and move PadDeck to Applications." \
      && ok "release v$MAC_VERSION publicado"
  fi
else
  echo "Pulado."
fi

# --- 4. Archive + upload --------------------------------------------------------
step "4/4 Enviar o app para o App Store Connect"
echo "Antes: o app precisa existir no App Store Connect (Apps › + › New App, bundle ID com.douglasneto.paddeck)."
if ask "O app já foi criado lá e você quer gerar o Archive e enviar agora?"; then
  ARCHIVE=app/build/PadDeck.xcarchive
  rm -rf "$ARCHIVE" app/build/export
  xcodebuild -project app/PadDeck.xcodeproj -scheme PadDeck -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" archive -quiet || fail "o Archive falhou"
  ok "Archive gerado"
  cat > app/build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><true/>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist app/build/ExportOptions.plist \
    -exportPath app/build/export -allowProvisioningUpdates || fail "o envio falhou (detalhes acima)"
  ok "build enviado: aparece em App Store Connect › TestFlight em ~15 minutos"
else
  echo "Pulado. (Pelo Xcode: Any iOS Device › Product › Archive › Distribute App.)"
fi

step "Falta fazer no site do App Store Connect"
cat <<TXT
  • Business › Agreements: Paid Apps Agreement + dados fiscais e bancários
  • Screenshots de iPhone 6,9" e iPad 13" (veja app/AppStore/RELEASE.md, passo 4)
  • Textos, URLs e notas para o revisor: app/AppStore/metadata-en.md e metadata-pt-BR.md
  • Preço, App Privacy ("Data Not Collected"), Age Rating (4+), selecionar o build › Submit
TXT
ok "pronto"
