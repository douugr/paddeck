# Publicar o PadDeck na App Store — passo a passo

Os textos da loja estão em `metadata-en.md` (idioma principal) e `metadata-pt-BR.md`.

## 1. Ligar o site (GitHub Pages) — uma vez

GitHub › `douugr/paddeck` › **Settings › Pages** › Source: **Deploy from a branch** › Branch `main`, pasta **/docs** › Save.

Em alguns minutos ficam no ar:
- https://douugr.github.io/paddeck/ (marketing)
- https://douugr.github.io/paddeck/support.html e /pt/suporte.html (suporte)
- https://douugr.github.io/paddeck/privacy.html e /pt/privacidade.html (privacidade)

## 2. Notarizar o app do Mac — uma vez + a cada versão

O revisor da Apple vai baixar o PadDeck para Mac: ele precisa abrir sem alertas de segurança.

Uma vez:
1. Xcode › Settings › Accounts › seu Apple ID › **Manage Certificates** › **+** › **Developer ID Application**.
2. Em https://account.apple.com › Login e Segurança › **Senhas de app**, crie uma senha para "notarytool".
3. No Terminal (Team ID em developer.apple.com › Membership):
   ```
   xcrun notarytool store-credentials paddeck-notary \
     --apple-id SEU_APPLE_ID --team-id SEU_TEAM_ID --password SENHA_DE_APP
   ```

A cada versão:
```
cd mac-agent
./build.sh notarize
gh release create v1.2 build/PadDeck-mac.zip -R douugr/paddeck --target main \
  -t "PadDeck 1.2 for Mac" -n "Signed and notarized by Apple. English menu. Download PadDeck-mac.zip, unzip and move PadDeck to Applications."
```
Bônus: com a assinatura Developer ID, a permissão de Acessibilidade não se perde mais a cada build.

## 3. App Store Connect — uma vez

1. **Business › Agreements**: aceite o **Paid Apps Agreement** e preencha dados fiscais e bancários (obrigatório para app pago; a liberação pode levar alguns dias).
2. **Apps › + › New App**: plataforma **iOS**, nome `PadDeck: Mac Keyboard & Mouse`, idioma principal **English (U.S.)**, bundle ID **com.douglasneto.paddeck**, SKU `paddeck-ios`, acesso total.
   (Se o bundle ID não aparecer: developer.apple.com › Identifiers › **+** › App IDs, ou rode o app uma vez no Xcode com o seu time, que o cria sozinho.)

## 4. Screenshots

Obrigatórias: **iPhone 6,9"** e **iPad 13"** (o app roda nos dois). Sugestão de 4 a 5 telas por aparelho:
trackpad + teclado · balão de acentos (segure o "c") · atalhos · teclado deitado · tela de conexão.

1. No Xcode, rode no simulador **iPhone 17 Pro Max** (ou 16 Pro Max) e depois **iPad Pro 13-inch (M4)**.
   O simulador encontra o PadDeck do seu Mac pela rede normalmente.
2. Capture com **⌘S** no Simulator (salva na Mesa) ou `xcrun simctl io booted screenshot tela.png`.
3. Para as telas em português: Product › Scheme › Edit Scheme › Run › Options › **App Language: Portuguese (Brazil)**.

## 5. Gerar o build e enviar

```
cd app
# defina DEVELOPMENT_TEAM no project.yml (ou escolha o time em Signing & Capabilities)
xcodegen && open PadDeck.xcodeproj
```
No Xcode: destino **Any iOS Device (arm64)** › **Product › Archive** › Organizer › **Distribute App** › **App Store Connect** › Upload.
A cada novo envio, aumente `CURRENT_PROJECT_VERSION` no `project.yml` (e `MARKETING_VERSION` em versões novas).

## 6. Preencher a versão e enviar para revisão

Em App Store Connect › PadDeck › versão 1.0:
- Textos, URLs e palavras-chave de `metadata-en.md`; adicione a localização **Portuguese (Brazil)** com `metadata-pt-BR.md`.
- Screenshots, **Build** (o que você enviou), **Copyright**.
- **Pricing and Availability**: preço (sugestão US$ 2,99) e países.
- **App Privacy**: "Data Not Collected"; URL da política de privacidade.
- **Age Rating**: tudo "None" → 4+.
- **App Review Information**: seus contatos e as **notas para o revisor** de `metadata-en.md`.
  Recomendo gravar um vídeo curto (tela do iPhone + Mac) e colocar o link nas notas.
- **Add for Review** › **Submit**.
