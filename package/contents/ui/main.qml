/*
 * Wi-Fi Generation — system tray applet.
 *
 * NetworkManager does not expose the Wi-Fi generation in any field (checked
 * 2026-08-15: the AP field list runs from NAME to DBUS-PATH and has no
 * generation). Plasma's network applet reads everything from it, so it has
 * nowhere to take that from. The kernel knows, via nl80211.
 *
 * Clicking opens the network list: a saved network connects in one click
 * (`network-control` is allow_active=yes, no password); a new one opens
 * Plasma's network module, which knows how to ask for a password safely.
 *
 * EVERY user-visible string goes through i18nd. The helper script emits
 * stable TOKENS and never prose, precisely so the words live here, where a
 * message catalogue can reach them.
 *
 * Appearance comes entirely from the theme — Kirigami and PlasmaComponents,
 * no hardcoded colour or measurement.
 */
import QtQuick
import QtQuick.Layouts
// Needed for the ScrollBar.vertical attached property — the component is
// Plasma's, but the attachment is defined by QtQuick.Controls.
import QtQuick.Controls as QQC2

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string dom: "plasma_applet_com.henrique.wifigeracao"

    // The script travels INSIDE the package and its path is resolved at
    // runtime. It used to be the author's home directory — on any other
    // machine the command would not resolve and the widget would fall silent,
    // the worst kind of defect for someone installing it.
    readonly property string script: {
        const u = Qt.resolvedUrl("../code/wifi-geracao").toString();
        return u.replace(/^file:\/\//, "");
    }

    // Invoked through `bash <path>` rather than executed directly, so the
    // execute bit does not matter. Plasmoid installers (Discover, the KDE
    // Store) unzip without preserving permissions, and a perfectly good
    // script would then refuse to run. The quotes cover paths with spaces.
    function cmd(args) {
        return "/bin/bash '" + script + "' " + args;
    }

    property bool   conectado: false
    property string geracao:   ""
    property string ssid:      ""
    property string rx:        ""
    property string tx:        ""
    property string sinal:     ""
    property string qualidade: ""
    property string canal:     ""
    property string largura:   ""
    property string numeroGeracao: ""
    property string banda:     ""
    property string avisoAcao: ""
    property string estado:    ""
    property bool   varrendo:  false

    // ---------------------------------------------------------------- textos
    //
    // Tokens in, translated words out. The mapping lives here because
    // gettext cannot reach into a shell script.
    function textoQualidade(t) {
        switch (t) {
        case "excellent": return i18nd(dom, "excellent");
        case "good":      return i18nd(dom, "good");
        case "fair":      return i18nd(dom, "fair");
        case "weak":      return i18nd(dom, "weak");
        case "veryweak":  return i18nd(dom, "very weak");
        default:          return i18nd(dom, "unknown");
        }
    }

    function textoBanda(b) {
        // The decimal separator differs by locale, so the number is built
        // from a translatable pattern rather than pasted together.
        switch (b) {
        case "2.4": return i18nd(dom, "2.4 GHz");
        case "5":   return i18nd(dom, "5 GHz");
        case "6":   return i18nd(dom, "6 GHz");
        default:    return "—";
        }
    }

    function textoGeracao(g) {
        // "Wi-Fi 6", "802.11 a/b/g" and the like are proper names and stay
        // as they are; only the absence of a name is translated.
        return g === "unknown" ? i18nd(dom, "Unknown") : g;
    }

    function textoSeguranca(s) {
        return s === "open" ? i18nd(dom, "open") : s;
    }

    // Lit arcs, 0 to 3. Connected NEVER draws zero: an earlier version let
    // "very weak" fall through to the default and painted a live -76 dBm
    // link as having no signal. Weak is weak, not absent.
    readonly property int barras: {
        if (!conectado) return 0;
        switch (qualidade) {
        case "excellent": return 3;
        case "good":      return 3;
        case "fair":      return 2;
        default:          return 1;
        }
    }

    ListModel { id: redes }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            const saida = (data["stdout"] || "").trim();
            disconnectSource(source);
            if (source.indexOf("--networks") >= 0) {
                if (source.indexOf("--scan") >= 0)
                    root.varrendo = false;
                root.montarRedes(saida);
            } else if (source.indexOf("--detail") >= 0) {
                root.aplicar(saida);
            } else if (source.indexOf("--connect") >= 0) {
                // The result goes ON SCREEN. An earlier version called nmcli
                // and ignored both output and exit code — it failed silently,
                // and "I clicked and nothing happened" had no diagnosis.
                root.mostrarResultado(saida);
                root.lerEstado();
                root.lerRedes();
            } else {
                root.lerEstado();
            }
        }
    }

    function lerEstado()  { exec.connectSource(cmd("--detail")); }
    // NetworkManager's cache: instant (0.25 s), but it goes stale.
    function lerRedes()   { exec.connectSource(cmd("--networks")); }
    // A real scan: ~4.5 s. Without it a live network vanishes from the list —
    // one at 80% signal was absent from the cache and returned on scanning.
    function varrerRedes() {
        root.varrendo = true;
        exec.connectSource(cmd("--networks --scan"));
    }

    function mostrarResultado(saida) {
        if (saida.length === 0) {
            root.avisoAcao = i18nd(dom, "No response from the system");
            return;
        }
        const corte = saida.indexOf("|");
        const tipo = corte < 0 ? saida : saida.substring(0, corte);
        const det  = corte < 0 ? ""    : saida.substring(corte + 1);
        if (tipo === "OK")
            root.avisoAcao = i18nd(dom, "Connected to %1", det);
        else if (det === "noname")
            root.avisoAcao = i18nd(dom, "No network given");
        else
            // The detail comes from nmcli, which the system already
            // localises — passed through rather than re-translated.
            root.avisoAcao = i18nd(dom, "Failed: %1", det);
    }

    function aplicar(linha) {
        if (linha === "nowifi") {
            root.conectado = false;
            root.estado = i18nd(dom, "No Wi-Fi adapter");
            root.numeroGeracao = "";
            return;
        }
        if (linha === "disconnected") {
            root.conectado = false;
            root.estado = i18nd(dom, "Disconnected");
            root.numeroGeracao = "";
            return;
        }
        const campos = linha.split("|");
        // The script promises 10 fields. Fewer means an unexpected reply.
        if (campos.length < 10) {
            root.conectado = false;
            root.estado = i18nd(dom, "Unknown");
            root.numeroGeracao = "";
            return;
        }
        root.conectado     = true;
        root.geracao       = campos[0];
        root.ssid          = campos[1];
        root.rx            = campos[2];
        root.tx            = campos[3];
        root.sinal         = campos[4];
        root.qualidade     = campos[5];
        root.canal         = campos[6];
        root.largura       = campos[7];
        root.numeroGeracao = campos[8];
        root.banda         = campos[9];
    }

    function montarRedes(saida) {
        redes.clear();
        if (saida.length === 0)
            return;
        const linhas = saida.split("\n");
        for (let i = 0; i < linhas.length; i++) {
            const c = linhas[i].split("|");
            if (c.length < 5) continue;
            redes.append({
                emUso:     c[0] === "1",
                sinalPct:  parseInt(c[1]) || 0,
                seguranca: c[2],
                salva:     c[3] === "1",
                nome:      c.slice(4).join("|")   // an SSID may contain "|"
            });
        }
    }

    function conectar(nome, salva) {
        if (salva) {
            root.avisoAcao = i18nd(dom, "Connecting to %1…", nome);
            // Single quotes with the apostrophe escaped: an SSID is
            // third-party text heading for a command line.
            const seguro = "'" + nome.replace(/'/g, "'\\''") + "'";
            exec.connectSource(cmd("--connect " + seguro));
        } else {
            // A new network needs a password. Asking for one inside this
            // widget would mean building a homemade credential box; Plasma's
            // own module already does it properly.
            root.avisoAcao = i18nd(dom, "Opening network settings…");
            exec.connectSource("kcmshell6 kcm_networkmanagement");
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.lerEstado();
            if (root.expanded) root.lerRedes();
        }
    }

    // `root.expanded`, not bare `expanded`: the bare name is read as an
    // injected handler parameter, a deprecated practice plasmashell warns
    // about in the journal on every load.
    onExpandedChanged: {
        if (root.expanded) {
            root.avisoAcao = "";
            root.lerRedes();     // cache: the list shows at once
            root.varrerRedes();  // scan: replaces it in ~4 s
        }
    }

    toolTipMainText: conectado
        ? (textoGeracao(geracao) + " · " + ssid)
        : estado
    toolTipSubText: conectado
        ? i18nd(dom, "%1/%2 Mb/s  ·  %3 dBm (%4)",
                rx, tx, sinal, textoQualidade(qualidade))
        : ""

    // DO NOT declare `preferredRepresentation`.
    //
    // `preferredRepresentation: compactRepresentation` does not mean "use the
    // compact one in a panel" — it means "use the compact one, full stop".
    // With it, the widget was stuck as an icon and the popup NEVER opened:
    // the click registered, `expanded` turned true, and nothing appeared.
    // Without it, Plasma decides by comparing available space to the limits
    // below: narrow panel → compact; click → expanded.
    switchWidth:  Kirigami.Units.gridUnit * 16
    switchHeight: Kirigami.Units.gridUnit * 16

    // ------------------------------------------------------------ tray icon
    // A plain Item, with NO MouseArea. Inside the tray it is the tray that
    // handles the click and toggles expansion; a MouseArea of ours on top
    // swallows the event before it gets there.
    compactRepresentation: Item {
        id: compacto

        SimboloWifi {
            anchors.centerIn: parent
            barras: root.barras
            numero: root.numeroGeracao
            // A tray icon does not take any size: it snaps to the standard
            // ladder (16, 22, 32…). Filling the whole square left the symbol
            // one step larger than its neighbours.
            tamanho: Kirigami.Units.iconSizes.roundedIconSize(
                Math.min(compacto.width, compacto.height))
        }
    }

    // -------------------------------------------------------------- popup
    fullRepresentation: Item {
        id: janela

        // Height follows the CONTENT. With a fixed height and a list set to
        // fillHeight, three networks left ~180 px of dead space between the
        // last row and the footer — it read as unfinished.
        readonly property int alturaLinha: Kirigami.Units.gridUnit * 2
        readonly property int alturaLista: Math.min(
            Math.max(redes.count, 1) * alturaLinha,
            Kirigami.Units.gridUnit * 14)   // ceiling: then it scrolls

        // implicitWidth/Height, not just the Layout hints. An Item with no
        // implicit size opens the popup at zero by zero: the click works,
        // the state turns expanded, and nothing shows on screen.
        implicitWidth:  Kirigami.Units.gridUnit * 20
        implicitHeight: coluna.implicitHeight + Kirigami.Units.largeSpacing * 2

        Layout.minimumWidth:    Kirigami.Units.gridUnit * 16
        Layout.preferredWidth:  Kirigami.Units.gridUnit * 20
        Layout.minimumHeight:   implicitHeight
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            id: coluna
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            // ---- header: the current connection --------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                SimboloWifi {
                    barras: root.barras
                    numero: root.numeroGeracao
                    tamanho: Kirigami.Units.iconSizes.large
                    Layout.preferredWidth:  implicitWidth
                    Layout.preferredHeight: implicitHeight
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaExtras.Heading {
                        level: 4
                        text: root.conectado ? root.ssid : root.estado
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.Label {
                        visible: root.conectado
                        text: root.textoGeracao(root.geracao) + "  ·  "
                              + root.textoBanda(root.banda)
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.Label {
                        visible: root.conectado
                        text: i18nd(root.dom, "%1/%2 Mb/s  ·  %3 dBm (%4)",
                                    root.rx, root.tx, root.sinal,
                                    root.textoQualidade(root.qualidade))
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Channel and width belong with the other facts about the
                    // current link. The i18n rewrite dropped the detail grid
                    // that used to carry them and they ended up shown
                    // nowhere — a regression introduced by that conversion.
                    PlasmaComponents.Label {
                        visible: root.conectado && root.canal.length > 0
                        text: i18nd(root.dom, "Channel %1  ·  %2",
                                    root.canal, root.largura)
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            PlasmaComponents.Label {
                visible: root.avisoAcao.length > 0
                text: root.avisoAcao
                font: Kirigami.Theme.smallFont
                opacity: 0.8
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    // The count is deliberately visible: an empty list is a
                    // diagnosis, not blank space.
                    text: i18ndp(root.dom, "%1 network nearby",
                                 "%1 networks nearby", redes.count)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    visible: root.varrendo
                    text: i18nd(root.dom, "scanning…")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh-symbolic"
                    enabled: !root.varrendo
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18nd(root.dom, "Scan again")
                    onClicked: root.varrerRedes()
                }
            }

            // ---- the network list ----------------------------------------
            //
            // A bare ListView with an explicit MouseArea per row, rather than
            // ScrollView + ItemDelegate. Fewer layers, fewer places for the
            // event to vanish.
            ListView {
                id: lista
                Layout.fillWidth: true
                // implicitHeight, não só preferredHeight: um ListView tem
                // implicitHeight ZERO por definição, então a altura da coluna
                // — e portanto a da janela — saía sem contar a lista. A
                // bandeja então impunha o mínimo dela e a diferença virava
                // vão morto distribuído entre as seções.
                implicitHeight: janela.alturaLista
                Layout.preferredHeight: janela.alturaLista
                model: redes
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 0

                QQC2.ScrollBar.vertical: PlasmaComponents.ScrollBar { }

                delegate: Rectangle {
                    width: lista.width
                    height: janela.alturaLinha
                    color: mouse.containsMouse && !model.emUso
                           ? Kirigami.Theme.highlightColor
                           : "transparent"
                    opacity: mouse.containsMouse && !model.emUso ? 0.35 : 1.0
                    radius: Kirigami.Units.cornerRadius

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (model.emUso) {
                                root.avisoAcao = i18nd(root.dom,
                                    "You are already on this network.");
                                return;
                            }
                            root.conectar(model.nome, model.salva);
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        SimboloWifi {
                            barras: model.sinalPct >= 67 ? 3
                                  : model.sinalPct >= 40 ? 2 : 1
                            numero: ""
                            tamanho: Kirigami.Units.iconSizes.small
                            Layout.preferredWidth:  implicitWidth
                            Layout.preferredHeight: implicitHeight
                        }

                        PlasmaComponents.Label {
                            text: model.nome
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.bold: model.emUso
                        }

                        PlasmaComponents.Label {
                            // Percentual não passa por catálogo: "%1%" fazia o gettext desconfiar
                            // do "%" final e rebaixar a tradução a fuzzy — e fuzzy fica em inglês.
                            text: model.sinalPct + "%"
                            opacity: 0.6
                            font: Kirigami.Theme.smallFont
                        }

                        Kirigami.Icon {
                            visible: model.seguranca !== "open"
                            source: "object-locked-symbolic"
                            opacity: model.salva ? 0.75 : 0.35
                            Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                    }
                }
            }

            // Espaçador explícito: com fillHeight em NENHUM item, a folga da
            // janela (a bandeja impõe uma altura mínima própria) acabava
            // distribuída ENTRE as seções — vão acima da lista e abaixo dela.
            // Dando um destino único à sobra, a lista encosta no cabeçalho e
            // o que resta vira respiro antes do rodapé, que lê como
            // intencional. Duas hipóteses minhas sobre a origem da folga
            // falharam; isto não depende de descobrir a origem.
            Item {
                Layout.fillHeight: true
                Layout.minimumHeight: 0
            }

            PlasmaComponents.Label {
                text: i18nd(root.dom,
                    "Dimmed padlock: network not saved yet — opens settings for the password.")
                font: Kirigami.Theme.smallFont
                opacity: 0.5
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }
        }
    }
}
