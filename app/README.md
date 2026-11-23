# PadDeck for current iPads and iPhones

The App Store version of PadDeck: Swift + UIKit (settings and editors in SwiftUI), iOS 16+,
iPad and iPhone. It speaks the same protocol as the iOS 8 app and uses the same Mac agent
(`../mac-agent`).

## Build

```
brew install xcodegen        # once
cd app
xcodegen                     # generates PadDeck.xcodeproj from project.yml
open PadDeck.xcodeproj
```

In Xcode, pick your team in **Signing & Capabilities** (or set `DEVELOPMENT_TEAM` in
`project.yml`), choose your iPad or iPhone and run.

The first launch asks for **Local Network** access: it's needed to find the Mac.

## Differences from the iOS 8 app

- Network.framework (TCP + UDP + Bonjour browsing) instead of BSD sockets
- Layout adapts to iPhone, iPad, Split View and both orientations
- Key haptics on iPhone
- Settings, connection and button editor in SwiftUI
- Same USB cable mode (usbmuxd) and same PIN pairing
