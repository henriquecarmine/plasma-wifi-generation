%global plasmoid_id com.henrique.wifigeracao

# NÃO grampear a data dos arquivos na data do changelog.
#
# O Fedora normaliza a mtime de tudo que entra no pacote para o
# SOURCE_DATE_EPOCH, que sai da data da última entrada do changelog — bom para
# compilação reprodutível, veneno para quem reconstrói o mesmo pacote no mesmo
# dia. O cache compilado de QML do Qt decide se está velho olhando a mtime do
# fonte: com a data grampeada, dois pacotes diferentes chegam ao disco com a
# MESMA mtime, e o painel continua executando o QML anterior.
#
# Isso custou uma tarde: o disco tinha o arquivo novo, o `grep` provava que o
# tipo removido não estava mais lá, e o Plasma insistia em "BarraSinal is not
# a type" — de um cache de 18:59 que ninguém tinha como suspeitar.
%global clamp_mtime_to_source_date_epoch 0

Name:           plasma-applet-wifi-generation
Version:        1.8.2
Release:        1%{?dist}
Summary:        Plasma applet showing the Wi-Fi generation (4/5/6/6E/7) in the system tray

License:        MIT
URL:            https://github.com/henriquecarmine/plasma-wifi-generation
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch

# Só instala arquivos de dados; nada a compilar.
BuildRequires:  coreutils

# O widget lê a geração do kernel via `iw` e lista/conecta redes via `nmcli`.
# Sem qualquer um dos dois ele fica mudo — por isso são Requires, não
# Recommends.
Requires:       iw
Requires:       NetworkManager
Requires:       bash
Requires:       plasma-workspace >= 6.0

%description
Shows in the system tray which Wi-Fi generation is in use - 4, 5, 6, 6E or 7 -
with the number overlaid on the signal fan, in the style of the Android
indicator.

NetworkManager does not expose the Wi-Fi generation in any field, and since
Plasma's network applet reads everything from it, that information appears
nowhere in the interface. The kernel knows, via nl80211; this applet reads
from there.

Clicking shows the real negotiated speed, band, channel, width and signal in
dBm, plus the list of nearby networks. A saved network connects in one click;
a new one opens Plasma's network module, which handles passwords safely.

Available in English, Portuguese (Brazil), Spanish and French.

%prep
%setup -q

%install
install -d %{buildroot}%{_datadir}/plasma/plasmoids/%{plasmoid_id}
cp -a %{plasmoid_id}/. %{buildroot}%{_datadir}/plasma/plasmoids/%{plasmoid_id}/

# O QML invoca o script por `bash <caminho>`, então o bit de execução não é
# obrigatório — mas mantê-lo permite rodar o script sozinho no terminal, que
# é útil para diagnóstico.
chmod 0755 %{buildroot}%{_datadir}/plasma/plasmoids/%{plasmoid_id}/contents/code/wifi-geracao

# Licença e README são entregues pelas macros %%license/%%files, não
# duplicados dentro do pacote de dados.
rm -f %{buildroot}%{_datadir}/plasma/plasmoids/%{plasmoid_id}/LICENSE
rm -f %{buildroot}%{_datadir}/plasma/plasmoids/%{plasmoid_id}/README.md

%files
%license %{plasmoid_id}/LICENSE
%doc %{plasmoid_id}/README.md
%{_datadir}/plasma/plasmoids/%{plasmoid_id}/

%changelog
* Tue Sep 01 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.8.2-1
- The scroll bar now APPEARS when the list has more networks than fit. It was
  there all along, but with no explicit policy it inherited the theme's, which
  keeps it transparent until the pointer comes near — so a list that really
  did scroll showed no bar at all, and nothing on screen said there were more
  networks below. A bar that only shows itself to someone who already knows it
  is there serves no purpose.
- The row now opens TWO gaps on the right: one for the bar, one between the
  bar and the padlock. The bar is drawn over the row rather than reserving
  space, and with a single gap the icon touched it — not clipped, but it read
  as clipped, and at 16 px nobody can tell the difference.
- THE LEFTOVER HEIGHT GOES TO THE LIST, not to a spacer. The tray imposes a
  minimum height of its own, almost always larger than the sections add up to,
  and that difference used to become dead space at the bottom: eighteen
  networks within reach, seven on screen, and an empty rectangle below the
  size of four more. The list now shows as many as fit and scrolls the rest.

* Tue Sep 01 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.8.1-1
- NOT MEASURED IS NOT BAD, and the difference decides which radio the machine
  moves to. Observed throughput only counts as a sample above 128 kB/s: below
  that what was watched is a clock widget and a browser tab — the background
  traffic of an idle machine — and not the capacity of the radio. Counting it
  as throughput gave zero on 30% of the score to a radio nobody had pushed
  anything through, so it lost to one that had been used, and the widget
  advised switching for lack of a sample rather than because of a measurement.
  With no sample the term now leaves the sum and the remaining weights are
  renormalised: the score says what is actually known — NAT depth, round trip,
  jitter and loss. On the network this was written against, the repeater goes
  from 43 to 62 and the router reads 93, and what separates them is the NAT
  depth alone, which is the real difference.

* Mon Aug 31 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.8-1
- ACCESS POINTS ARE NOW MEASURED, NOT GUESSED. Signal strength measures the
  antenna, not the way out: a repeater negotiating 700 Mb/s that delivers 5
  Mb/s of internet beats, on dBm, a router negotiating 300 that delivers 200.
  Each radio now carries a score built from NAT depth, round trip to the
  internet, jitter, packet loss and the largest throughput real use has ever
  reached through it. The list shows the score in place of the percentage
  wherever a measurement exists, and the percentage moves to the tooltip.
- The measurement runs by itself right after a connection comes up, which is
  the one moment it costs no interruption at all, and refuses to repeat
  itself within ten minutes. Throughput is watched for free — the widget
  already reads the interface counters every two seconds — and the active
  download test lives behind a button because it spends data.
- NAT DEPTH is what catches a badly placed repeater when nothing else does.
  Measured here, latency was excellent (10 ms, 1.2 ms of jitter, no loss) on
  a link sitting behind two private hops: the computer on one subnet, the
  phone in the same house on another, unable to see each other. Only hops in
  RFC1918 count. RFC 6598 (100.64/10) does not: providers number access
  transport from it as often as they use it for CGNAT, and a subscriber with
  a fixed public address sees that hop without being translated at all.
- The padlock no longer disappears on a network without a password: it OPENS.
  Hiding it took the icon out of the row's layout, so one open network pulled
  every column of every row out of line.
- Security is read PER RADIO from the kernel, not per network name from
  NetworkManager, which aggregates the two into one answer. A radio in mixed
  WPA/WPA2 mode now says so instead of claiming plain WPA2 — WPA1 brings
  TKIP, and hiding that is the opposite of what the column is for.
- Connections are made by profile UUID, chosen by the security of the target
  radio, and the next candidate is tried when the first fails. On a radio in
  transition mode, which speaks both WPA2 and WPA3, the tie goes to WPA2:
  that is the profile which also works on the PSK-only repeater, and it is
  the only one that roams across the whole house.
- When no saved profile speaks what a radio requires, one is DERIVED from an
  existing profile of the same network, keeping the same passphrase — WPA2
  and WPA3 use the same one, so there is nothing to ask anyone. The copy is
  made by NetworkManager itself; this widget never reads the password. The
  derived profile is discarded if it fails to connect.
- Duplicate profiles for one network are reported, with a way to remove the
  extra ones. Two profiles under one name mean the system picks by chance,
  and the losing pick may reach only one of the radios.
- The header says which RADIO the machine is on and whether it may leave:
  locked to one, on the preferred one, or roaming freely. The network name
  alone does not tell the router in the living room from the repeater on the
  balcony.
- A radio can be PREFERRED by MAC, with a signal cut-off and a dead band, so
  the machine keeps it while it holds and gives it up only when it does not.
  Automatic switching is optional and off by default.
- The tray icon follows the DEFAULT ROUTE: the cable icon when the cable
  carries the traffic. The dot that used to mark a second link is gone — it
  said nothing to anyone who had not read the code that drew it.
- Access points are forgotten after five minutes, and a manual scan forgets
  whatever it did not hear. Networks that no longer exist used to stay in the
  list forever, and pressing rescan only made the list longer.
- The context menu opens the system's Wi-Fi settings instead of an about box
  for a widget that has nothing to configure.
- Fixed: the merge of remembered access points let the OLD signal reading
  overwrite the one just measured, so the list showed the previous scan's
  strength — the worst possible number for deciding which radio to enter.
- Fixed: helpers were defined after the code that called them, so the first
  --connect of a session read an empty security for the target radio.
- Fixed: reading tab-separated records with `read` collapsed consecutive
  tabs, so an empty field shifted every column after it — a profile bound to
  no radio reported its timestamp as a MAC address.
- Fixed: `--rede` and `--taxa` answered "nowifi" on a machine with no
  wireless card, hiding the cable it was asked about.
- build.sh now refuses to package QML carrying a duplicate property name. Qt
  only complains when loading, and the popup comes up blank; it cost a
  version that was packaged and installed before anyone opened it.

* Sun Aug 16 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.7-1
- The network list became a TABLE: the name on the left, then the same fan
  symbol the tray shows — arcs for strength, generation number inside — the
  percentage and the checkbox. Every column but the name has a fixed width,
  so they begin at the same place on every row.
- The fan replaced two columns of text, one for the radio address and one
  spelling out "Wi-Fi 6". A symbol already read every day on the panel says
  the same thing in a square, and the address only tells rows apart when
  several carry the same name — so it appears only in that mode.
- One row per ACCESS POINT rather than per name, with a button that shows
  routers and repeaters. It is the only way to see a repeater standing beside
  the main unit — and a checkbox on the row ties the connection to one of
  them, for the day the configuration page lives on the other side of the
  house.
- Two orders, one per mode: by signal in the normal list, where the strongest
  is what you want; alphabetical when every device is shown, so a repeater
  stands next to the unit it repeats. By signal alone the two end up separated
  by neighbours, and comparing them is why that mode exists. Within one name,
  the strongest still comes first.
- The address, gateway and public IP are in the interface row's tooltip, and
  clicking the row copies the three. Reading an address off a screen to type
  it somewhere else is how a digit gets lost.
- File mtimes are no longer clamped to the changelog date. Fedora normalises
  them for reproducible builds; Qt's compiled-QML cache decides staleness by
  the source mtime, so two different builds of the same version reached the
  disk stamped identically and the panel kept running the previous QML.
- The address panel now answers the whole question in one line: the address
  this machine holds, the gateway it leaves through, and the address the
  internet sees. It replaces a "dhcp" badge whose number was drawn grey on
  grey — opacity on the chip dimmed the label with it.
- Unknown security is no longer reported as "open". Our list remembers access
  points NetworkManager has already dropped, and an open padlock over a
  protected network is a lie told on the dangerous side.

* Sun Aug 16 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.6-1
- Addresses are now a LIST per interface, shown as chips: add, remove, and a
  suggest button that scans from .240 downwards — a range rarely inside a
  home DHCP pool — and only offers what does not answer a ping. Taking an
  address already in use knocks the other machine off the network, and it
  does not always come back on its own.
- Adding a static address does NOT switch the profile away from DHCP. The
  NetworkManager accepts static addresses alongside `auto`, which is what
  lets a maintenance IP be hung on an interface without giving up the working
  network — exactly what was missing the day a factory-default router had to
  be reached without dropping the house.
- Chips act immediately; Apply is left for method, gateway and DNS. A button
  that stores list changes for later forces the user to remember what was
  asked for.
- Method can be set per interface: DHCP, manual, or PPPoE — the last one only
  when a PPPoE profile already exists. Creating one would mean typing a
  username and password into a panel form and passing them on a command line,
  where any process reads them with `ps`.
- The profile lookup has three fallbacks, because the case that matters is the
  worst one: with the cable DISCONNECTED there is no active connection, and
  that is exactly when someone opens the widget to fix the address.
- The scan now shows each network's generation, read from the kernel's scan
  cache with `iw scan dump` — which, unlike `iw scan`, runs without root.
  NetworkManager exposes no generation at all and wpa_supplicant denies bus
  access to a plain user.
- Generations are REMEMBERED between scans. The kernel cache holds only the
  last scan while NetworkManager lists networks heard minutes ago, so without
  memory the number blinked in and out for the same network — worse than not
  showing it.
- Fixed: the gateway tooltip was drawn behind the row above. Siblings drawn
  later cover earlier ones, and the tooltip is anchored to its own row; the
  row now rises a layer while the mouse is on it.
* Sun Aug 16 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.5-1
- The popup now lists EVERY physical interface, one row each: medium on the
  left (channel and width for Wi-Fi, negotiated link speed for wired), live
  rates in the middle, address on the right. Discovered by plugging a cable:
  the previous version spoke only of the wireless interface, so with a cable
  carrying the traffic it showed an address nobody was using.
- An interface is listed if it has an address OR a carrier. Requiring an
  address hid the freshly plugged cable during the minutes it spends asking
  for DHCP — which is exactly when its owner opens the popup to check.
- The gateway moved to the row's tooltip. Measured, the ip+gw pair alone took
  more width than the other three blocks together, and the gateway is the
  most repeated datum on screen: usually identical on both interfaces.
- The address label is the row's ELASTIC element (fillWidth, minimumWidth 0,
  elide from the left). With a rigid spacer there, nothing yielded when the
  sum passed the window width and the row burst out to the right.
- Tray symbol follows the links: the fan with the generation number for
  Wi-Fi, the theme's own network-wired-symbolic for cable, and the fan with a
  dot in the bottom-LEFT corner when two links carry DIFFERENT gateways —
  load balancing or redundancy. Same gateway on both is not a mix: it is one
  exit reached by two paths.
- The wired symbol is NOT drawn by hand. An RJ45 socket was drawn in the
  Canvas and thrown away: the theme already ships network-wired-symbolic,
  which Plasma uses for wired networks, tints with the row and survives a
  theme change. Same lesson the weather widget taught earlier the same day.
- Network is read every 15 s even with the popup CLOSED, because the tray
  symbol depends on it; otherwise the icon would only learn about the cable
  when somebody opened the popup.
- Fixed: two assignments to properties that no longer existed survived in
  onExpandedChanged, and the exception aborted the rest of the handler —
  which is where the address and counter reads are requested. The popup
  opened looking exactly like the version before this feature.
* Sun Aug 16 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.4-1
- The popup now carries the address and the traffic: IP and gateway on the
  same line as the channel, aligned right, and live download/upload rates.
- A switch turns the radio on and off. Its subcommand sits BEFORE anything
  that depends on the interface: with the radio off there is no `iw dev` at
  all, and the switch has to keep answering in exactly that state, otherwise
  it turns off and never comes back.
- Rates are computed in QML from raw byte counters the script prints.
  Sleeping a second inside the script to measure there would block Plasma's
  executable engine on every refresh.
- Counters are sampled every 2 s and ONLY while the popup is open; a widget
  that spends the day closed has no reader to pay for.
- A negative counter delta is the interface coming back up, not traffic: it
  reads as zero instead of a gigabyte spike.
- The address line is a FULL-WIDTH row under the header. Placed inside the
  text column, as it was first written, it pushed the switch and the rates
  out of the frame.
* Sun Aug 16 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.3-1
- Popup height follows its content; the tray's leftover space now has a
  single destination instead of being spread between sections.
- Channel and width are shown again: the i18n rewrite had dropped the detail
  grid that carried them.

* Sun Aug 16 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.2-1
- Internationalised: interface strings now go through gettext.
- Translations: English (source), Portuguese (Brazil), Spanish, French.
- The helper script emits stable tokens instead of prose, so every
  user-visible word is reachable by the message catalogue.

* Sun Aug 16 2026 Henrique Carmine <henriquecarmine@gmail.com> - 1.1-1
- Primeira versão empacotada.
- Símbolo desenhado à mão com o número da geração sobreposto, centrado pela
  tinta e não pela linha teórica.
- Lista de redes com varredura forçada na abertura: a lista vinda só do cache
  do NetworkManager omitia redes vivas.
- Script embutido no pacote e caminho resolvido em execução.
