%global plasmoid_id com.henrique.wifigeracao

Name:           plasma-applet-wifi-generation
Version:        1.6
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
