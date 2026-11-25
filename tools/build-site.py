#!/usr/bin/env python3
"""Builds docs/index.html (English) and docs/pt/index.html (Portuguese) from one template.

Usage: python3 tools/build-site.py
The support and privacy pages are written by hand.
"""
import html
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs")
MAC_ZIP = "https://github.com/douugr/paddeck/releases/latest/download/PadDeck-mac.zip"
RELEASES = "https://github.com/douugr/paddeck/releases/latest"
REPO = "https://github.com/douugr/paddeck"
CYDIA = "https://douugr.github.io/repo/"
APPSTORE = "https://apps.apple.com/app/id6838387257"

# (line, name EN, name PT, trackpad, key, accent) — same values as the App Store app (Theme.swift) and ipad/src/PDTheme.m
SWATCHES = [
    ("MacBook Neo", "Silver", "Prateado", "#D0D1D5", "#F7F7F9", "#0A6FE0"),
    ("MacBook Neo", "Blush", "Blush", "#E5CEC9", "#FBF1EF", "#C25B73"),
    ("MacBook Neo", "Citrus", "Cítrico", "#DDE1A8", "#F8F9E3", "#6F7F0A"),
    ("MacBook Neo", "Indigo", "Índigo", "#2F355E", "#434A80", "#93A5FF"),
    ("MacBook Air", "Sky Blue", "Azul-céu", "#C5D4E0", "#1C1C1E", "#2F7DC0"),
    ("MacBook Air", "Starlight", "Estelar", "#DDD4C5", "#1C1C1E", "#9A733C"),
    ("MacBook Air", "Midnight", "Meia-noite", "#272D3C", "#343B50", "#5E9CFF"),
    ("MacBook Pro", "Space Black", "Preto-espacial", "#1E1F21", "#303134", "#0A84FF"),
    ("iMac", "Blue", "Azul", "#CADDEF", "#FFFFFF", "#2D6BB4"),
    ("iMac", "Purple", "Roxo", "#DDD4EE", "#FFFFFF", "#7653B5"),
    ("iMac", "Pink", "Rosa", "#F2D5D8", "#FFFFFF", "#CF4A6B"),
    ("iMac", "Orange", "Laranja", "#F6D7C2", "#FFFFFF", "#DC6427"),
    ("iMac", "Yellow", "Amarelo", "#F4E6B6", "#FFFFFF", "#C9970E"),
    ("iMac", "Green", "Verde", "#D0E7D0", "#FFFFFF", "#3A8A4B"),
]

T = {
    "en": dict(
        lang="en", base="", other="pt/", other_label="Português",
        title="PadDeck — Keyboard, trackpad and shortcuts for your Mac",
        desc="Turn your iPhone or iPad into a wireless keyboard, trackpad and shortcut deck for your Mac. Free Mac app, over Wi-Fi or a USB cable.",
        nav_home="Home", nav_support="Support", nav_privacy="Privacy",
        support="support.html", privacy="privacy.html",
        hero_h="Your iPhone and iPad, now a keyboard, trackpad and shortcut deck for your Mac.",
        hero_p="Control your Mac from the couch, run a presentation, or keep a row of one-tap shortcuts next to your keyboard. Over Wi-Fi or a USB cable.",
        dl="Download for Mac", dl_meta="Free · macOS 12 or later · Apple silicon and Intel",
        appstore="Get it on the App Store", appstore_meta="iPhone and iPad · iOS 16 or later",
        dl_mac="PadDeck for Mac",
        pair_note="PadDeck has two parts that work together: the app on your iPhone or iPad, where you touch, and the free PadDeck for Mac, which moves the pointer and types. The Mac app does nothing on its own.",
        alt_ipad="PadDeck on iPad: trackpad with a full Mac keyboard",
        alt_iphone="PadDeck on iPhone: shortcut deck",
        feat_h="Everything a Mac trackpad and keyboard do",
        feats=[
            ("Trackpad", "Tap to click, two-finger right click and scrolling with momentum, double-tap and drag, three-finger swipes for Mission Control and Spaces."),
            ("Scroll strip", "Slide one finger along the edge to scroll, handy when you hold the iPhone in one hand."),
            ("Mac keyboard", "⌘ ⌥ ⌃ ⇧, esc, F1–F12, arrows and media keys. Hold a letter for accents. Works with any Mac keyboard layout."),
            ("Shortcut deck", "45 buttons in the style of a Stream Deck: keyboard shortcuts, text snippets, apps, websites and media keys."),
            ("Wi-Fi or cable", "Finds your Mac by itself and pairs with a 4-digit PIN. Plug in a USB cable for the lowest latency, no PIN needed."),
            ("Private", "Talks only to your own Mac. No accounts, no ads, no tracking, no data collected."),
        ],
        colors_h="Match your Mac",
        colors_p="Pick the color of your MacBook Neo, Air, Pro or iMac, and PadDeck takes on the same finish: trackpad, keys and accent.",
        steps_h="Set up in a minute",
        steps=[
            ("Get the iPhone or iPad app", "Download PadDeck from the App Store on the iPhone or iPad you'll use as a trackpad and keyboard."),
            ("Install PadDeck for Mac", "Download it, move it to Applications and open it. A keyboard icon appears in the menu bar."),
            ("Allow Accessibility", "In System Settings › Privacy & Security › Accessibility, turn PadDeck on so it can move the pointer and type."),
            ("Connect", "Open PadDeck on your iPhone or iPad, pick your Mac and enter the PIN shown in the menu bar. With a USB cable it connects by itself."),
        ],
        trust_h="Safe to open",
        trust=[
            ("Notarized by Apple", "Signed with a Developer ID and checked by Apple: macOS opens it with just the usual confirmation for apps downloaded from the internet."),
            ("Open source", "The Mac app and the protocol are on GitHub under the MIT license."),
            ("Tiny and quiet", "A menu bar app of about 200 KB. It only listens while it's open, and you choose whether it starts at login."),
        ],
        legacy_h="Got an old jailbroken iPad?",
        legacy_p="PadDeck also runs on iPads with iOS 8 to 10 (tested on an iPad 3). Add the repo below in Cydia and search for PadDeck.",
        legacy_btn="Open the Cydia repo",
        help_p="Questions? See the <a href=\"support.html\">support page</a> or <a href=\"https://github.com/douugr/paddeck/issues\">open an issue on GitHub</a>.",
        footer="Mac, MacBook, iMac, iPhone and iPad are trademarks of Apple Inc. PadDeck is not affiliated with Apple.",
        all_releases="All versions",
    ),
    "pt": dict(
        lang="pt-BR", base="../", other="../", other_label="English",
        title="PadDeck — Teclado, trackpad e atalhos para o seu Mac",
        desc="Transforme o seu iPhone ou iPad em teclado, trackpad e painel de atalhos sem fio para o Mac. App gratuito para Mac, pelo Wi-Fi ou por cabo USB.",
        nav_home="Início", nav_support="Suporte", nav_privacy="Privacidade",
        support="suporte.html", privacy="privacidade.html",
        hero_h="O seu iPhone e iPad viram teclado, trackpad e painel de atalhos do Mac.",
        hero_p="Controle o Mac do sofá, passe os slides de uma apresentação ou tenha uma fileira de atalhos de um toque ao lado do teclado. Pelo Wi-Fi ou por cabo USB.",
        dl="Baixar para Mac", dl_meta="Grátis · macOS 12 ou mais novo · Apple silicon e Intel",
        appstore="Baixar na App Store", appstore_meta="iPhone e iPad · iOS 16 ou mais novo",
        dl_mac="PadDeck para Mac",
        pair_note="O PadDeck tem duas partes que funcionam juntas: o app no iPhone ou iPad, onde você toca, e o PadDeck para Mac, gratuito, que move o cursor e digita. O app do Mac sozinho não faz nada.",
        alt_ipad="PadDeck no iPad: trackpad com teclado de Mac completo",
        alt_iphone="PadDeck no iPhone: painel de atalhos",
        feat_h="Tudo o que o trackpad e o teclado do Mac fazem",
        feats=[
            ("Trackpad", "Toque para clicar, clique direito e rolagem com dois dedos e com inércia, toque duplo e arraste, gestos de três dedos para Mission Control e mesas."),
            ("Faixa de rolagem", "Deslize um dedo pela borda para rolar, prático quando você segura o iPhone com uma mão."),
            ("Teclado de Mac", "⌘ ⌥ ⌃ ⇧, esc, F1–F12, setas e teclas de mídia. Segure uma letra para acentos. Funciona com qualquer layout de teclado do Mac."),
            ("Painel de atalhos", "45 botões no estilo Stream Deck: atalhos de teclado, textos prontos, apps, sites e teclas de mídia."),
            ("Wi-Fi ou cabo", "Encontra o Mac sozinho e pareia com um PIN de 4 dígitos. Ligue um cabo USB para o menor atraso, sem PIN."),
            ("Privado", "Fala só com o seu próprio Mac. Sem contas, sem anúncios, sem rastreamento, nenhum dado coletado."),
        ],
        colors_h="Com a cor do seu Mac",
        colors_p="Escolha a cor do seu MacBook Neo, Air, Pro ou iMac e o PadDeck fica com o mesmo acabamento: trackpad, teclas e cor de destaque.",
        steps_h="Pronto em um minuto",
        steps=[
            ("Baixe o app no iPhone ou iPad", "Baixe o PadDeck na App Store, no iPhone ou iPad que vai servir de trackpad e teclado."),
            ("Instale o PadDeck para Mac", "Baixe, mova para Aplicativos e abra. Um ícone de teclado aparece na barra de menus."),
            ("Permita a Acessibilidade", "Em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade, ligue o PadDeck para ele mover o cursor e digitar."),
            ("Conecte", "Abra o PadDeck no iPhone ou iPad, escolha o seu Mac e digite o PIN que aparece na barra de menus. Com cabo USB, conecta sozinho."),
        ],
        trust_h="Seguro para abrir",
        trust=[
            ("Notarizado pela Apple", "Assinado com Developer ID e verificado pela Apple: o macOS abre com apenas a confirmação de sempre para apps baixados da internet."),
            ("Código aberto", "O app do Mac e o protocolo estão no GitHub, com licença MIT."),
            ("Leve e discreto", "Um app de barra de menus com cerca de 200 KB. Só escuta a rede enquanto está aberto, e você decide se ele abre com o Mac."),
        ],
        legacy_h="Tem um iPad antigo com jailbreak?",
        legacy_p="O PadDeck também roda em iPads com iOS 8 a 10 (testado num iPad 3). Adicione o repositório abaixo no Cydia e procure por PadDeck.",
        legacy_btn="Abrir o repositório do Cydia",
        help_p="Dúvidas? Veja a <a href=\"suporte.html\">página de suporte</a> ou <a href=\"https://github.com/douugr/paddeck/issues\">abra uma issue no GitHub</a>.",
        footer="Mac, MacBook, iMac, iPhone e iPad são marcas da Apple Inc. O PadDeck não tem relação com a Apple.",
        all_releases="Todas as versões",
    ),
}

CSS = """
:root{color-scheme:light dark;--bg:#f5f5f7;--card:#fff;--text:#1d1d1f;--muted:#6e6e73;--accent:#0a64d6;--line:rgba(0,0,0,.08)}
@media (prefers-color-scheme:dark){:root{--bg:#0e0e10;--card:#1c1c1f;--text:#f5f5f7;--muted:#98989d;--accent:#4aa3ff;--line:rgba(255,255,255,.1)}}
*{box-sizing:border-box}
body{margin:0;font:17px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",Helvetica,Arial,sans-serif;background:var(--bg);color:var(--text);-webkit-font-smoothing:antialiased}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
.wrap{max-width:1040px;margin:0 auto;padding:0 24px}
.top{display:flex;align-items:center;gap:12px;padding:18px 0}
.top img{width:34px;height:34px;border-radius:8px}.top b{font-size:19px;margin-right:auto}
.top nav{display:flex;gap:20px;font-size:15px}.top nav a{color:var(--muted)}.top nav a:hover{color:var(--text);text-decoration:none}
.hero{text-align:center;padding:48px 0 8px}
.hero img.icon{width:112px;height:112px;border-radius:25px;box-shadow:0 10px 30px rgba(0,0,0,.18)}
.hero h1{font-size:clamp(32px,5.2vw,54px);line-height:1.08;letter-spacing:-.02em;margin:26px auto 16px;max-width:860px}
.hero p.lead{font-size:clamp(18px,2.2vw,22px);color:var(--muted);max-width:720px;margin:0 auto}
.cta{margin:30px 0 8px;display:flex;flex-direction:column;align-items:center;gap:10px}
.btn{display:inline-flex;align-items:center;gap:10px;background:var(--accent);color:#fff;border-radius:980px;padding:14px 28px;font-size:18px;font-weight:600}
.btn:hover{text-decoration:none;filter:brightness(1.08)}.btn svg{width:20px;height:20px;fill:currentColor}
.meta{color:var(--muted);font-size:14px}
.pair{display:flex;justify-content:center;align-items:flex-start;gap:18px;margin:32px auto 0;flex-wrap:wrap}
.part{display:flex;flex-direction:column;align-items:center;gap:8px;position:relative;max-width:300px}
.part .num{width:24px;height:24px;border-radius:50%;background:var(--text);color:var(--bg);font-size:13px;font-weight:700;display:flex;align-items:center;justify-content:center}
.plus{font-size:28px;color:var(--muted);margin-top:38px}
.btn.alt{background:var(--card);color:var(--text);box-shadow:inset 0 0 0 1px var(--line)}
.note{max-width:620px;margin:20px auto 0;font-size:15px;color:var(--muted);background:var(--card);border-radius:14px;padding:12px 18px;text-align:left}
@media (max-width:640px){.plus{margin:0}.pair{flex-direction:column;align-items:center}}
.devices{position:relative;max-width:980px;margin:48px auto 0;padding-bottom:40px}
.devices .ipad{width:84%;height:auto;border-radius:22px;border:10px solid #1d1d1f;box-shadow:0 30px 60px rgba(0,0,0,.25);display:block}
.devices .iphone{position:absolute;right:0;bottom:0;width:22%;height:auto;border-radius:30px;border:7px solid #1d1d1f;box-shadow:0 24px 50px rgba(0,0,0,.35)}
section{padding:64px 0 8px}
h2{font-size:clamp(28px,3.6vw,40px);letter-spacing:-.015em;line-height:1.12;text-align:center;margin:0 0 12px}
.sub{color:var(--muted);text-align:center;max-width:680px;margin:0 auto 32px;font-size:19px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}
.card{background:var(--card);border-radius:20px;padding:24px 26px}
.card h3{margin:0 0 6px;font-size:19px}.card p{margin:0;color:var(--muted);font-size:16px}
.swatches{display:grid;grid-template-columns:repeat(auto-fill,minmax(118px,1fr));gap:14px}
.sw{background:var(--card);border-radius:16px;padding:12px;text-align:center;font-size:14px}
.sw .mini{height:64px;border-radius:10px;padding:7px;display:flex;flex-direction:column;gap:5px;margin-bottom:8px;border:1px solid var(--line)}
.sw .pad{flex:1;border-radius:5px}.sw .keys{display:flex;gap:3px;height:14px}.sw .keys i{flex:1;border-radius:3px}
.sw small{display:block;color:var(--muted);font-size:12px}
.steps{counter-reset:s;display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px}
.steps .card{position:relative;padding-top:58px}
.steps .card:before{counter-increment:s;content:counter(s);position:absolute;top:20px;left:26px;width:28px;height:28px;border-radius:50%;background:var(--accent);color:#fff;font-weight:700;font-size:15px;display:flex;align-items:center;justify-content:center}
.legacy{display:flex;gap:24px;align-items:center;flex-wrap:wrap}.legacy div{flex:1;min-width:260px}
.legacy code{background:var(--bg);border-radius:8px;padding:3px 8px;font-size:15px}
.btn2{display:inline-block;border:1px solid var(--accent);color:var(--accent);border-radius:980px;padding:10px 20px;font-weight:600}
.btn2:hover{text-decoration:none;background:var(--accent);color:#fff}
.end{text-align:center;padding:72px 0 24px}
footer{color:var(--muted);font-size:13px;text-align:center;padding:32px 0 48px;border-top:1px solid var(--line);margin-top:40px}
@media (max-width:640px){.top nav{gap:14px;font-size:14px}.devices .ipad{width:100%;border-width:6px;border-radius:14px}.devices .iphone{width:30%;right:-4px;bottom:-10px;border-width:5px;border-radius:20px}.devices{padding-bottom:0}}
"""

DL = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a1 1 0 0 1 1 1v9.6l3.3-3.3a1 1 0 1 1 1.4 1.4l-5 5a1 1 0 0 1-1.4 0l-5-5a1 1 0 1 1 1.4-1.4l3.3 3.3V4a1 1 0 0 1 1-1zM5 19h14a1 1 0 1 1 0 2H5a1 1 0 1 1 0-2z"/></svg>'


PHONE = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 2h8a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zm0 2v16h8V4H8zm3 13h2a1 1 0 1 1 0 2h-2a1 1 0 1 1 0-2z"/></svg>'


def esc(s):
    return html.escape(s, quote=True)


def build(code):
    t = T[code]
    b = t["base"]
    cards = "".join(f'<div class="card"><h3>{esc(h)}</h3><p>{esc(p)}</p></div>' for h, p in t["feats"])
    steps = "".join(f'<div class="card"><h3>{esc(h)}</h3><p>{esc(p)}</p></div>' for h, p in t["steps"])
    trust = "".join(f'<div class="card"><h3>{esc(h)}</h3><p>{esc(p)}</p></div>' for h, p in t["trust"])
    sw = "".join(
        f'<div class="sw" role="img" aria-label="{esc(line)} {esc(en if code == "en" else pt)}">'
        f'<div class="mini" style="background:{pad}"><div class="pad" style="background:{pad};filter:brightness(.97)"></div>'
        f'<div class="keys">{"".join(f"<i style=background:{acc if i == 4 else key}></i>" for i in range(5))}</div></div>'
        f'{esc(en if code == "en" else pt)}<small>{esc(line)}</small></div>'
        for line, en, pt, pad, key, acc in SWATCHES)
    return f"""<!DOCTYPE html>
<html lang="{t['lang']}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(t['title'])}</title>
<meta name="description" content="{esc(t['desc'])}">
<meta property="og:title" content="{esc(t['title'])}">
<meta property="og:description" content="{esc(t['desc'])}">
<meta property="og:image" content="https://douugr.github.io/paddeck/img/ipad-main-{code}.jpg">
<link rel="icon" href="{b}icon-512.png"><link rel="apple-touch-icon" href="{b}icon-512.png">
<link rel="alternate" hreflang="en" href="https://douugr.github.io/paddeck/">
<link rel="alternate" hreflang="pt-BR" href="https://douugr.github.io/paddeck/pt/">
<style>{CSS}</style></head>
<body>
<div class="wrap">
<header class="top"><img src="{b}icon-512.png" alt=""><b>PadDeck</b>
<nav><a href="{t['support']}">{esc(t['nav_support'])}</a><a href="{t['privacy']}">{esc(t['nav_privacy'])}</a><a href="{t['other']}" hreflang="{'pt-BR' if code == 'en' else 'en'}">{esc(t['other_label'])}</a></nav></header>

<div class="hero">
<img class="icon" src="{b}icon-512.png" alt="">
<h1>{esc(t['hero_h'])}</h1>
<p class="lead">{esc(t['hero_p'])}</p>
<div class="pair">
<div class="part"><span class="num">1</span><a class="btn" href="{APPSTORE}">{PHONE}{esc(t['appstore'])}</a><span class="meta">{esc(t['appstore_meta'])}</span></div>
<div class="plus" aria-hidden="true">+</div>
<div class="part"><span class="num">2</span><a class="btn alt" href="{MAC_ZIP}">{DL}{esc(t['dl'])}</a><span class="meta">{esc(t['dl_meta'])} · <a href="{RELEASES}">{esc(t['all_releases'])}</a></span></div>
</div>
<p class="note">{esc(t['pair_note'])}</p>
</div>

<div class="devices">
<img class="ipad" src="{b}img/ipad-main-{code}.jpg" alt="{esc(t['alt_ipad'])}" width="1600" height="1200">
<img class="iphone" src="{b}img/iphone-deck-{code}.jpg" alt="{esc(t['alt_iphone'])}" width="560" height="1218" loading="lazy">
</div>

<section><h2>{esc(t['feat_h'])}</h2><div class="grid" style="margin-top:28px">{cards}</div></section>

<section><h2>{esc(t['colors_h'])}</h2><p class="sub">{esc(t['colors_p'])}</p><div class="swatches">{sw}</div></section>

<section><h2>{esc(t['steps_h'])}</h2><div class="steps" style="margin-top:28px">{steps}</div>
<div class="cta" style="flex-direction:row;justify-content:center;flex-wrap:wrap"><a class="btn" href="{APPSTORE}">{PHONE}{esc(t['appstore'])}</a><a class="btn alt" href="{MAC_ZIP}">{DL}{esc(t['dl'])}</a></div></section>

<section><h2>{esc(t['trust_h'])}</h2><div class="grid" style="margin-top:28px">{trust}</div></section>

<section><div class="card legacy"><div><h3>{esc(t['legacy_h'])}</h3><p>{esc(t['legacy_p'])} <code>douugr.github.io/repo</code></p></div>
<a class="btn2" href="{CYDIA}">{esc(t['legacy_btn'])}</a></div></section>

<p class="end meta">{t['help_p']}</p>
<footer>© 2026 Douglas Rodrigues Neto · <a href="{REPO}">github.com/douugr/paddeck</a><br>{esc(t['footer'])}</footer>
</div>
</body></html>
"""


for code in ("en", "pt"):
    path = os.path.join(ROOT, "index.html" if code == "en" else "pt/index.html")
    with open(path, "w") as f:
        f.write(build(code))
    print("wrote", os.path.relpath(path, os.path.join(ROOT, "..")))
