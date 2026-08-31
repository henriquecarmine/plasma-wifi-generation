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
- **The tray symbol follows the DEFAULT ROUTE:** the fan with the generation
  number when Wi-Fi carries the traffic, the theme's `network-wired-symbolic`
  when the cable does. Having a gateway is not leaving through it — with both
  links up there are two gateways and only one moves packets. The other link
  is named in the tooltip.
- **The network list is a table**: the name on the left, then the same fan
  symbol the tray uses — arcs for strength, generation number inside — the
  percentage, and the padlock. Every column but the name has a fixed width,
  so they start at the same place on every row: aligned columns are read
  straight down, and comparing is the whole point of a list.
- **The generation of every scanned network**, not only the connected one,
  inside the fan rather than spelled out in a column of its own. It comes
  from the kernel's scan cache via `iw scan dump`, which runs without root —
  NetworkManager exposes no generation and wpa_supplicant denies bus access
  to a plain user. Generations are remembered between scans, because the
  kernel cache holds only the last one while NetworkManager lists networks
  heard minutes ago.
- **One row per access point**, with a button that shows routers and
  repeaters instead of only the strongest of each name. It is the only way to
  see a repeater standing beside the main unit. That mode adds the radio's
  address and two buttons per row, which are different things on purpose: the
  **pin** locks the connection to one exact radio and keeps it there, for the
  day the configuration page lives on the other side of the house; the
  **star** marks a radio as PREFERRED — the machine returns to it while its
  signal stays above a cut-off you set, and gives it up below. A repeater
  placed badly reaches further than the router it repeats, so a system that
  picks by signal alone picks the repeater every time; when that repeater does
  NAT over NAT, the computer stops seeing the phone in the same house, and
  nothing on screen says why.
- **The padlock is never hidden, only opened.** A network with no password
  gets an OPEN padlock. Making the icon invisible took it out of the row's
  layout and pulled every other column out of line — one open network
  misaligned the whole list.
- **Connections are made by profile UUID**, chosen by the security of the
  target radio, with the next candidate tried when the first fails. A house
  whose router speaks WPA3-SAE and whose repeater speaks only WPA2-PSK ends up
  with two saved profiles under the same name; connecting by name is a
  lottery, and the losing ticket asks for the password again on a network that
  is already saved. Duplicates are reported in the popup, with a way to remove
  the extra ones.
- **Access points are forgotten**: five minutes of memory in normal use, and a
  manual scan drops whatever it did not hear. Otherwise the list only ever
  grew, and networks that no longer exist stayed in it forever.
- **Access points are MEASURED, not guessed.** Signal strength measures the
  antenna, not the way out — a repeater negotiating 700 Mb/s that delivers 5
  Mb/s of internet beats, on dBm, a router negotiating 300 that delivers 200.
  Each radio carries a score, and the list shows it in place of the
  percentage wherever a measurement exists:

  | part | weight | why |
  |---|---|---|
  | NAT depth | 35% | it is what breaks the local network, and no other number reveals it |
  | real throughput | 30% | the question actually being asked |
  | round trip | 20% | |
  | jitter | 10% | |
  | packet loss | 5% | |

  Signal is not in the formula at all. It is the tiebreaker between radios
  nobody has measured yet.

  The measurement runs by itself right after a connection comes up — the one
  moment it costs no interruption — and refuses to repeat within ten minutes.
  Throughput is watched for free, from the interface counters the widget
  already reads every two seconds; the active download test is behind a
  button, because it spends data.
- **NAT depth is what catches a badly placed repeater** when nothing else
  does. On the network this was written against, latency was excellent — 10
  ms, 1.2 ms of jitter, no loss — on a link sitting behind two private hops,
  with the computer on one subnet and the phone in the same house on another.
  Only RFC1918 hops count; RFC 6598 (100.64/10) does not, because providers
  number access transport from it as often as they use it for CGNAT, and a
  subscriber with a fixed public address sees that hop without being
  translated at all.
- **Addresses as a list per interface**, shown as chips you can add and
  remove, with a suggest button that offers a free address verified by ping.
  A static address can be hung on an interface **without leaving DHCP** —
  which is how you reach a factory-default router without dropping the
  network you are using.
- **What DHCP handed out, in one reading**: the address this machine holds,
  the gateway it leaves through, and the address the internet sees. The last
  one is asked of an outside service **once per popup opening** — a tray
  widget that phones a server every few seconds leaks presence and carries no
  reader. The same three facts are in the interface row's tooltip, and
  clicking the row copies them.

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
