%global plasmoid_id com.henrique.wifigeracao

Name:           plasma-applet-wifi-generation
Version:        1.4
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
