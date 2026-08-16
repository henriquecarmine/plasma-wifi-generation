# Texto pronto para o anúncio no store.kde.org

**Categoria:** Plasma 6 Add-Ons → Plasma Widgets
**Licença:** MIT
**Arquivo a enviar:** `wifi-generation-1.2.plasmoid`

---

## Título

```
Wi-Fi Generation
```

## Resumo (uma linha)

```
Shows which Wi-Fi generation you are actually connected to — 4, 5, 6, 6E or 7 — right in the system tray.
```

## Descrição

```
Plasma 6 system tray widget that shows which Wi-Fi generation you are
actually connected to — 4, 5, 6, 6E or 7 — with the number overlaid on the
signal fan, in the style of the Android indicator.

WHY IT EXISTS

NetworkManager does not expose the Wi-Fi generation in any field. The full
list of properties it offers about an access point goes from NAME to
DBUS-PATH and has nothing about 802.11ax/ac/n:

  NAME  SSID  BSSID  MODE  CHAN  FREQ  RATE  BANDWIDTH
  SIGNAL  BARS  SECURITY  WPA-FLAGS  RSN-FLAGS  DEVICE

Since Plasma's network applet reads everything from NetworkManager, it has
nowhere to take that from. The kernel knows, through nl80211 — which is what
`iw` queries. That is where this widget reads from.

The generation comes from the prefix of the negotiated rate:

  EHT-MCS -> Wi-Fi 7 (802.11be)
  HE-MCS  -> Wi-Fi 6 / 6E (802.11ax)
  VHT-MCS -> Wi-Fi 5 (802.11ac)
  MCS     -> Wi-Fi 4 (802.11n)
  none    -> 802.11 a/b/g

Wi-Fi 6 on the 6 GHz band is shown as 6E — the distinction is the band, not
the protocol.

WHAT IT SHOWS

- Tray: the Wi-Fi fan with the generation number overlaid. Arcs light up with
  signal strength; a weak link still LOOKS connected, with translucent arcs
  instead of blank ones.
- Tooltip: generation, network, speed and signal.
- On click: band, channel, width, up/down rate, signal in dBm with a
  plain-language quality, and the list of nearby networks sorted by signal.

CONNECTING

A network you already saved connects in one click, no password — the
org.freedesktop.NetworkManager.network-control action is allow_active=yes, so
the active session already has permission.

A new network opens Plasma's own network module, which is what knows how to
ask for a password safely. This widget deliberately has no credential box of
its own.

REQUIREMENTS

- Plasma 6.0 or newer
- iw           (package: iw)
- nmcli        (package: NetworkManager)

TRANSLATIONS

English (source), Portugues (Brasil), Espanol, Francais.

The helper script emits stable tokens and never prose, precisely so every
user-visible word lives in the QML where gettext can reach it. Adding a
language means copying po/pt_BR.po, translating it, and compiling the
catalogue into contents/locale/<lang>/LC_MESSAGES/.
```

## Tags

```
wifi, network, systray, indicator, networkmanager, wifi6, plasma6
```

---

## O que ainda depende de você

**Capturas de tela.** A loja mostra o anúncio muito melhor com duas: o ícone
na bandeja e a janela aberta com a lista de redes. Posso gerar.

**Repositório público.** A URL declarada no RPM é
`https://github.com/henriquecarmine/plasma-wifi-generation` e ainda não
existe. Ou cria o repositório, ou tira a URL — link quebrado num anúncio pega
mal, e a loja costuma pedir a origem do código.

## Cadastro

Use **e-mail e senha**, não o botão do Google. O login social do Chrome já
está preso na conta `cesar.school` e escolhe ela sozinha; o formulário comum
aceita `henriquecarmine@gmail.com` como texto e não tem como errar.
