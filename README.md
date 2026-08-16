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
- **Address and traffic:** IP and gateway on the same line as the channel,
  aligned to the right edge, plus live download and upload rates sampled
  every two seconds while the popup is open.
- **A switch for the radio**, which keeps working with the radio off — the
  subcommand behind it never touches the wireless interface.

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
