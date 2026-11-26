# Security Policy

## Supported Versions

Only the latest release of PadDeck receives security fixes. This covers the Mac companion app (`mac-agent`), the legacy iPad app (`ipad`) and the PadDeck app on the App Store.

## Reporting a Vulnerability

Please **do not open a public issue** for security problems.

Report it privately through GitHub: open the [Security tab](https://github.com/douugr/paddeck/security) of this repository and click **Report a vulnerability**.

Please include:

- which part is affected (Mac companion, iPhone/iPad app or legacy iPad app) and its version
- steps to reproduce, or a proof of concept
- the impact you expect

I'll reply within 7 days and keep you updated until a fix is released. Once it's fixed, you'll be credited in the release notes if you'd like.

## Scope

PadDeck talks only to your own Mac, over your local network (Wi-Fi) or a USB cable. Of particular interest are issues that would let another device on the same network pair with or control a Mac without the PIN, or read what is typed.
