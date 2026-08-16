# Publicar no store.kde.org

**Categoria:** Plasma 6 Add-Ons → Plasma Widgets
**Licença:** MIT
**Arquivo a enviar:** `dist/wifi-generation.plasmoid`
**Repositório:** https://github.com/henriquecarmine/plasma-wifi-generation

O arquivo **não leva versão no nome** de propósito: a loja lê a versão do
`metadata.json` dentro do pacote, e repetir o número no nome quebraria todo
caminho escrito a cada lançamento.

## O passo que só você pode dar

O envio é pela **página da loja, com login**. Não existe caminho de linha de
comando com as credenciais que estão nesta máquina, então o `.plasmoid`, os
textos e as capturas ficam prontos aqui e o clique final é seu:

1. Entrar em https://store.kde.org — **e-mail e senha**, não o botão do
   Google. O login social do Chrome já está preso na conta `cesar.school` e
   escolhe ela sozinha; o formulário comum aceita `henriquecarmine@gmail.com`
   como texto e não tem como errar.
2. *Add Product* → categoria **Plasma 6 Add-Ons → Plasma Widgets**.
3. Colar título, resumo, descrição e tags daqui.
4. Enviar `dist/wifi-generation.plasmoid` e as duas capturas de
   `screenshots/`.

## Capturas

- `screenshots/01-tray.png` — o ícone na bandeja, entre os vizinhos.
- `screenshots/02-popup.png` — a janela aberta, uma linha por rede.
- `screenshots/03-repeaters.png` — o modo que mostra roteadores e
  repetidores: quatro rádios anunciando `wifi_zone`, em ordem alfabética e do
  mais forte para o mais fraco, cada um com o seu endereço.

**Em inglês, de propósito.** A loja é internacional e o anúncio é escrito em
inglês; captura em português obrigaria o leitor a traduzir a tela para
entender o que está vendo. Basta abrir com o idioma trocado:

```bash
LANGUAGE=en_US LANG=en_US.UTF-8 plasmawindowed com.henrique.wifigeracao
spectacle -a -b -n -o janela.png       # -a captura só a janela ativa
```

A terceira precisa do modo ligado, que só existe depois de um clique. Para
tirá-la sem depender disso, copie `package/`, troque `mostrarTodos` para
`true` e o `Id` do `metadata.json` para um nome próprio, instale com
`kpackagetool6 --type Plasma/Applet --install`, fotografe e **desinstale**.
Nada disso encosta no pacote de verdade.

**Confira o que aparece na foto.** Uma captura anterior mostrava, sem querer,
o **IP público da máquina** numa dica aberta — mostrá-lo na própria tela é uma
coisa, publicá-lo numa loja indexada é outra, e não se desfaz. Antes de subir:
dica aberta, endereço de saída, nome de rede vizinha.

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
  instead of blank ones. With a cable and Wi-Fi carrying DIFFERENT gateways
  at once, a dot in the corner says so — the same gateway on both is one exit
  reached by two paths, and is not drawn as two.
- Tooltip: generation, network, speed and signal.
- On click: band, channel, width, up/down rate, and signal in dBm with a
  plain-language quality.
- One row per interface, wired included: the medium on the left, live
  download and upload in the middle, the address on the right. The row's
  tooltip carries the gateway and the address the internet sees, and clicking
  the row copies the three.
- The network list as a table: the name, then the same fan symbol with the
  generation of THAT network inside, the percentage, and a checkbox. Every
  column but the name has a fixed width, so they begin at the same place on
  every row.
- A button that shows routers and repeaters instead of only the strongest of
  each name — the only way to see a repeater standing beside the unit it
  repeats. Alphabetical there, by signal in the normal list. The checkbox
  ties the connection to one exact radio, for the day the configuration page
  lives on the other side of the house.
- Addresses as a list per interface: add, remove, and a suggest button that
  offers a free address verified by ping. A static address can be hung on an
  interface WITHOUT leaving DHCP, which is how you reach a factory-default
  router without dropping the network you are on.

The generation of each scanned network comes from the kernel's scan cache via
`iw scan dump`, which runs without root. It is remembered between scans,
because that cache holds only the last one while NetworkManager lists
networks heard minutes ago.

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
wifi, network, systray, indicator, networkmanager, wifi6, repeater, plasma6
```
