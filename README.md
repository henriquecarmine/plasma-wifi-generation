# Wi-Fi Generation — a widget for KDE Plasma 6

Shows in the system tray **which Wi-Fi generation you are actually connected
to** — 4, 5, 6, 6E or 7 — with the number overlaid on the signal fan, in the
style of the Android indicator. Clicking opens the real negotiated speed and
the list of nearby networks, with one-click connection.

## Why it exists

**NetworkManager does not expose the Wi-Fi generation in any field.** The
complete list of properties it offers about an access point runs from `NAME`
to `DBUS-PATH` and has nothing about 802.11ax/ac/n:

```
NAME  SSID  BSSID  MODE  CHAN  FREQ  RATE  BANDWIDTH
SIGNAL  BARS  SECURITY  WPA-FLAGS  RSN-FLAGS  DEVICE
```

Since Plasma's network applet reads everything from NetworkManager, it would
have nowhere to take that from even if it wanted to. The **kernel** knows, via
nl80211 — which is what `iw` queries. That is where this widget reads from.

The generation comes from the prefix of the negotiated bitrate:

| prefix | generation |
|---|---|
| `EHT-MCS` | Wi-Fi 7 (802.11be) |
| `HE-MCS`  | Wi-Fi 6 / 6E (802.11ax) |
| `VHT-MCS` | Wi-Fi 5 (802.11ac) |
| `MCS`     | Wi-Fi 4 (802.11n) |
| none      | 802.11 a/b/g |

Wi-Fi 6 on the 6 GHz band becomes **6E** — the distinction is the band, not
the protocol.

## What it shows

- **In the tray:** the Wi-Fi fan with the generation number overlaid. Arcs
  light up with signal strength; a weak link still *looks* connected, with
  translucent arcs rather than blank ones.
- **In the tooltip:** generation, network, speed and signal.
- **On click:** band, channel, width, up/down rate, signal in dBm with a
  plain-language quality, and the list of networks sorted by signal.
- **One row per interface**, wired included: the medium on the left (channel
  and width for Wi-Fi, negotiated link speed for cable), live download and
  upload in the middle, the address on the right. The gateway lives in the
  row's tooltip — measured, it was the widest and most repeated datum on the
  line, usually identical on both interfaces.
- An interface appears if it has an address **or** a carrier, so a cable
  plugged a second ago shows up as "1000 Mb/s · no address" while it asks for
  DHCP, instead of being invisible.
- **A switch for the radio**, which keeps working with the radio off — the
  subcommand behind it never touches the wireless interface.
- **The tray symbol follows the links:** the fan with the generation number
  for Wi-Fi, the theme's `network-wired-symbolic` for cable, and the fan with
  a dot in the bottom-left corner when two links carry different gateways —
  load balancing or redundancy. The same gateway on both is not a mix: it is
  one exit reached by two paths.
- **The generation of every scanned network**, not only the connected one:
  the number sits beside each name in the list. It comes from the kernel's
  scan cache via `iw scan dump`, which runs without root — NetworkManager
  exposes no generation and wpa_supplicant denies bus access to a plain user.
  Generations are remembered between scans, because the kernel cache holds
  only the last one while NetworkManager lists networks heard minutes ago.
- **Addresses as a list per interface**, shown as chips you can add and
  remove, with a suggest button that offers a free address verified by ping.
  A static address can be hung on an interface **without leaving DHCP** —
  which is how you reach a factory-default router without dropping the
  network you are using.

## Connecting

A network you have **already saved** connects in one click, with no password —
the `org.freedesktop.NetworkManager.network-control` action is
`allow_active=yes`, so the active session already holds the permission.

A **new** network opens Plasma's own network module, which is what knows how
to ask for a password safely. This widget deliberately has no credential box
of its own: passwords belong to the system component, not to a third-party
applet.

## Requirements

- Plasma **6.0** or newer
- `iw` — reads the generation and signal (package `iw`)
- `nmcli` — lists networks and connects (package `NetworkManager`)

## Translations

English (source), **Português (Brasil)**, **Español**, **Français**.

The helper script emits stable tokens and never prose, precisely so every
user-visible word lives in the QML where gettext can reach it. To add a
language, copy `po/pt_BR.po`, translate, and compile into
`contents/locale/<lang>/LC_MESSAGES/plasma_applet_com.henrique.wifigeracao.mo`.

## License

MIT — see [LICENSE](LICENSE).
