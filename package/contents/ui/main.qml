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

    // ---- rede e tráfego ------------------------------------------------
    //
    // UMA LINHA POR INTERFACE. Cada uma tem o seu endereço, o seu gateway e o
    // seu tráfego; a primeira versão mostrava só a sem fio e escondia metade
    // da rede no dia em que um cabo foi plugado.
    ListModel { id: interfaces }   // tipo, dev, ip, gw, link, down, up

    // dev -> {rx, tx, ms} da leitura anterior. A taxa é a diferença dividida
    // pelo tempo, e quem tem relógio aqui é o QML.
    property var contadores: ({})

    function montarInterfaces(saida) {
        const vistos = {};
        const linhas = saida.split("\n").filter(function (l) { return l.length > 0; });
        for (let i = 0; i < linhas.length; i++) {
            const c = linhas[i].split("|");
            const dev = c[1] || "";
            if (dev.length === 0) continue;
            vistos[dev] = true;
            let achou = -1;
            for (let j = 0; j < interfaces.count; j++)
                if (interfaces.get(j).dev === dev) { achou = j; break; }
            const dados = {
                "tipo": c[0] || "cabo", "dev": dev,
                "ip": c[2] || "", "gw": c[3] || "", "link": c[4] || ""
            };
            // Atualizar em vez de recriar: recriando, as taxas piscavam a
            // cada leitura de endereço, porque a linha nascia zerada.
            if (achou >= 0) {
                interfaces.setProperty(achou, "tipo", dados.tipo);
                interfaces.setProperty(achou, "ip",   dados.ip);
                interfaces.setProperty(achou, "gw",   dados.gw);
                interfaces.setProperty(achou, "link", dados.link);
            } else {
                dados.down = 0; dados.up = 0; dados.saida = "";
                interfaces.append(dados);
            }
        }
        for (let k = interfaces.count - 1; k >= 0; k--)
            if (!vistos[interfaces.get(k).dev]) interfaces.remove(k);
        if (root.expanded) root.pedirSaidas();
    }

    // O IP com que cada interface aparece na internet.
    //
    // Pergunta a um serviço EXTERNO, então é feita uma única vez por abertura
    // do balão e só para interface que tenha gateway — sem saída não há o que
    // perguntar. Num widget que passa o dia aberto de vez em quando, isso é
    // uma consulta por vez que se olha; num laço de 15 segundos seria avisar
    // um servidor de fora a cada vez que a máquina respira.
    property var pediuSaida: ({})

    function pedirSaidas() {
        for (let i = 0; i < interfaces.count; i++) {
            const it = interfaces.get(i);
            if (!it.gw || it.gw.length === 0) continue;
            if (root.pediuSaida[it.dev]) continue;
            root.pediuSaida[it.dev] = true;
            exec.connectSource(cmd("--saida " + it.dev));
        }
    }

    function saidaDe(dev) {
        for (let i = 0; i < interfaces.count; i++)
            if (interfaces.get(i).dev === dev) return interfaces.get(i).saida || "";
        return "";
    }

    // Dica da linha da interface: quem é, por onde sai e com que cara aparece
    // lá fora. O gateway mora aqui desde que se mediu que, na linha, ele era
    // o dado mais largo e o menos consultado.
    function dicaInterface(dev, gw, saida) {
        let t = dev;
        if (gw && gw.length > 0)    t += "  ·  " + i18nd(dom, "gateway %1", gw);
        if (saida && saida.length > 0) t += "  ·  " + i18nd(dom, "out %1", saida);
        return t + "\n" + (root.copiado ? i18nd(dom, "Copied")
                                        : i18nd(dom, "Click to copy"));
    }

    // A confirmação da cópia vive na PRÓPRIA dica, onde o olho já está, e
    // apaga sozinha. Escrita como linha no balão, ela empurrava a lista para
    // baixo e ficava lá pedindo para ser lida de novo — aviso que sobrevive
    // ao momento vira ruído.
    property bool copiado: false
    Timer {
        id: relogioCopia
        interval: 1600
        onTriggered: root.copiado = false
    }

    // Copiar sem depender de programa externo: um TextEdit escondido leva o
    // texto ao mesmo QClipboard que o resto da área de trabalho usa. A
    // alternativa seria chamar `wl-copy`, que nem toda instalação tem — e
    // widget não deve exigir pacote para um botão de copiar.
    TextEdit {
        id: transferencia
        visible: false
        width: 0
        height: 0
    }

    function copiarEndereco(ip, gw, saida) {
        const t = i18nd(dom, "IP %1 · gateway %2 · out %3",
                        ip || "—", gw || "—", saida || "—");
        transferencia.text = t;
        transferencia.selectAll();
        transferencia.copy();
        root.copiado = true;
        relogioCopia.restart();
    }

    function medirTaxa(saida) {
        const agora = Date.now();
        const linhas = saida.split("\n").filter(function (l) { return l.length > 0; });
        for (let i = 0; i < linhas.length; i++) {
            const c = linhas[i].split("|");
            const dev = c[0];
            const rx = parseFloat(c[1]), tx = parseFloat(c[2]);
            if (!dev || isNaN(rx) || isNaN(tx)) continue;
            const ant = root.contadores[dev];
            if (ant && agora > ant.ms) {
                const dt = (agora - ant.ms) / 1000;
                // Diferença negativa não é tráfego: é o contador reiniciando
                // quando a interface cai e volta. Zerar é mais honesto que
                // mostrar um pico de gigabytes.
                const dr = rx - ant.rx, dtx = tx - ant.tx;
                for (let j = 0; j < interfaces.count; j++) {
                    if (interfaces.get(j).dev !== dev) continue;
                    interfaces.setProperty(j, "down", dr  >= 0 ? dr  / dt : 0);
                    interfaces.setProperty(j, "up",   dtx >= 0 ? dtx / dt : 0);
                }
            }
            root.contadores[dev] = { "rx": rx, "tx": tx, "ms": agora };
        }
    }

    // Unidades não passam por catálogo: "kB/s" e "MB/s" são as mesmas em toda
    // parte, e o gettext rebaixaria a tradução por causa da barra.
    function textoTaxa(bps) {
        if (bps < 1024) return Math.round(bps) + " B/s";
        if (bps < 1048576) return (bps / 1024).toFixed(bps < 10240 ? 1 : 0) + " kB/s";
        return (bps / 1048576).toFixed(1) + " MB/s";
    }

    property bool radioLigado: true

    // ---- configuração de endereço --------------------------------------
    // Índice da linha com o formulário aberto, ou -1. Um de cada vez: dois
    // formulários abertos numa janela deste tamanho é ruído, não recurso.
    property int linhaConfig: -1
    property string cfgDev: ""
    property string cfgPerfil: ""
    property string cfgMetodo: "auto"
    property string cfgEndereco: ""
    property string cfgGateway: ""
    property string cfgDns: ""
    property string cfgPppoe: ""
    property string cfgNovo: ""
    // O endereço que o DHCP entregou, e o IP com que esta interface aparece
    // para o mundo. Os dois são RETRATO: ninguém os digita, ninguém os
    // apaga — por isso não viram ficha, viram a linha de leitura.
    property string cfgIpAuto: ""
    property string cfgSaida: ""
    property bool   cfgSaidaPerguntada: false
    // Endereços FIXOS da interface aberta, os que estão escritos no perfil.
    // Só eles: um endereço de DHCP não se remove nem se edita, e enfileirá-lo
    // aqui com um "×" desbotado prometia um botão que não faz nada.
    ListModel { id: enderecos }

    function montarEnderecos(saida) {
        enderecos.clear();
        root.cfgIpAuto = "";
        const linhas = saida.split("\n");
        const fixos = {};
        for (let i = 0; i < linhas.length; i++) {
            const c = linhas[i].split("|");
            if (c[0] === "metodo") root.cfgMetodo = (c[1] || "").indexOf("manual") >= 0 ? "manual" : "auto";
            else if (c[0] === "fixo" && c[1]) fixos[c[1]] = true;
        }
        for (const f in fixos) enderecos.append({ "texto": f });
        // O primeiro endereço montado que NÃO está no perfil é o do DHCP.
        for (let j = 0; j < linhas.length; j++) {
            const c = linhas[j].split("|");
            if (c[0] === "ativo" && c[1] && !fixos[c[1]] && root.cfgIpAuto.length === 0)
                root.cfgIpAuto = c[1];
        }
    }

    // O gateway não vem do formulário: já está na linha da interface, lido do
    // sistema. Buscá-lo aqui evita perguntar duas vezes a mesma coisa.
    function gatewayDe(dev) {
        for (let i = 0; i < interfaces.count; i++)
            if (interfaces.get(i).dev === dev) return interfaces.get(i).gw;
        return "";
    }

    function abrirConfig(indice, dev) {
        root.linhaConfig = indice;
        root.cfgDev = dev;
        root.avisoAcao = "";
        root.cfgNovo = "";
        // O IP de saída já costuma ter sido perguntado quando o balão abriu.
        // Perguntar de novo aqui seria segunda consulta externa para a mesma
        // resposta.
        root.cfgSaida = root.saidaDe(dev);
        root.cfgSaidaPerguntada = root.cfgSaida.length === 0;
        if (root.cfgSaidaPerguntada)
            exec.connectSource(cmd("--saida " + dev));
        exec.connectSource(cmd("--perfil " + dev));
        exec.connectSource(cmd("--enderecos " + dev));
    }

    function sugerirEndereco() {
        exec.connectSource(cmd("--sugerir " + root.cfgDev));
    }
    function adicionarEndereco() {
        const e = root.cfgNovo.trim();
        if (e.length === 0) {
            root.avisoAcao = i18nd(dom, "Type the address as 192.168.1.50/24");
            return;
        }
        exec.connectSource(cmd("--addip " + root.cfgDev + " '" + e + "'"));
        root.cfgNovo = "";
    }
    function removerEndereco(texto) {
        exec.connectSource(cmd("--delip " + root.cfgDev + " '" + texto + "'"));
    }

    function aplicarConfig() {
        const d = root.cfgDev;
        if (root.cfgMetodo === "auto") {
            exec.connectSource(cmd("--aplicar " + d + " auto"));
        } else if (root.cfgMetodo === "pppoe") {
            exec.connectSource(cmd("--aplicar " + d + " pppoe '" + root.cfgPppoe + "'"));
        } else {
            // Endereços já foram aplicados um a um pelas fichas; aqui vai o
            // que resta do modo manual. Sem nenhum endereço fixo, mudar para
            // manual deixaria a interface sem IP — pior que o estado atual.
            if (enderecos.count === 0) {
                root.avisoAcao = i18nd(dom, "Add at least one address first");
                return;
            }
            let lista = [];
            for (let i = 0; i < enderecos.count; i++)
                lista.push(enderecos.get(i).texto);
            exec.connectSource(cmd("--aplicar " + d + " manual '" + lista.join(",")
                + "' '" + root.cfgGateway.trim() + "' '" + root.cfgDns.trim() + "'"));
        }
        root.linhaConfig = -1;
    }

    // Qual símbolo a bandeja mostra. Regra do dono: dois enlaces com saída
    // para rede e GATEWAYS DIFERENTES ao mesmo tempo — balanceamento ou
    // redundância — pedem o símbolo misto; se só um estiver conectado,
    // aparece o dele.
    //
    // Gateways IGUAIS não são mix: é a mesma saída alcançada por dois
    // caminhos, e mostrar duas marcas aí seria dizer o que não há.
    readonly property string modoSimbolo: {
        let comGw = [];
        for (let i = 0; i < interfaces.count; i++) {
            const it = interfaces.get(i);
            if (it.gw && it.gw.length > 0) comGw.push(it);
        }
        if (comGw.length >= 2) {
            const distintos = {};
            for (let j = 0; j < comGw.length; j++) distintos[comGw[j].gw] = true;
            if (Object.keys(distintos).length >= 2) return "mix";
        }
        if (comGw.length === 1) return comGw[0].tipo === "cabo" ? "cabo" : "wifi";
        return "wifi";
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
            } else if (source.indexOf("--radio") >= 0) {
                root.radioLigado = (saida === "on");
                // O rádio mudou: tudo o que dependia dele está velho.
                root.lerEstado();
                root.lerRede();
            } else if (source.indexOf("--perfil") >= 0) {
                const c = saida.split("|");
                root.cfgPerfil   = c[0] || "";
                root.cfgMetodo   = (c[1] || "auto").indexOf("manual") >= 0 ? "manual" : "auto";
                root.cfgEndereco = (c[2] || "").split(",")[0];
                root.cfgGateway  = c[3] || "";
                root.cfgDns      = (c[4] || "").split(",")[0];
                root.cfgPppoe    = c[5] || "";
            } else if (source.indexOf("--enderecos") >= 0) {
                root.montarEnderecos(saida);
            } else if (source.indexOf("--sugerir") >= 0) {
                const c = saida.split("|");
                if (c[0] === "livre") root.cfgNovo = c[1];
                else root.avisoAcao = i18nd(dom, "No free address found in this range");
            } else if (source.indexOf("--addip") >= 0 || source.indexOf("--delip") >= 0) {
                root.mostrarResultado(saida);
                if (root.cfgDev.length > 0)
                    exec.connectSource(cmd("--enderecos " + root.cfgDev));
                root.lerRede();
            } else if (source.indexOf("--aplicar") >= 0) {
                root.mostrarResultado(saida);
                root.lerEstado();
                root.lerRede();
            } else if (source.indexOf("--rede") >= 0) {
                root.montarInterfaces(saida);
            } else if (source.indexOf("--taxa") >= 0) {
                root.medirTaxa(saida);
            } else if (source.indexOf("--saida") >= 0) {
                // A resposta não diz de quem é: quem diz é o comando que a
                // pediu. Com duas interfaces, guardar no lugar errado
                // mostraria o IP do cabo na linha do wifi.
                const dev = source.substring(source.indexOf("--saida") + 8).trim();
                for (let i = 0; i < interfaces.count; i++)
                    if (interfaces.get(i).dev === dev)
                        interfaces.setProperty(i, "saida", saida);
                if (dev === root.cfgDev) {
                    root.cfgSaidaPerguntada = false;
                    root.cfgSaida = saida;
                }
            } else if (source.indexOf("--desfixar") >= 0) {
                // Resposta própria: "Conectado a X" seria mentira aqui, já
                // que soltar a amarra de propósito não reconecta nada.
                root.avisoAcao = saida.indexOf("OK|") === 0
                    ? i18nd(root.dom, "%1 is free to use any access point again.",
                            saida.substring(3))
                    : i18nd(root.dom, "Could not release this network.");
                root.lerRedes();
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
    function lerRede()    { exec.connectSource(cmd("--rede")); }
    function lerRadio()   { exec.connectSource(cmd("--radio")); }
    function alternarRadio(ligar) {
        root.avisoAcao = "";
        exec.connectSource(cmd("--radio " + (ligar ? "on" : "off")));
    }
    // Mostrar cada rádio separadamente, em vez de só o mais forte de cada
    // nome. Desligado por padrão: no dia a dia repetir a mesma rede quatro
    // vezes é ruído. Ligado, é a única forma de ver o repetidor ao lado do
    // principal — e de escolher a qual entrar.
    property bool mostrarTodos: false
    readonly property string argTodos: mostrarTodos ? " --todos" : ""

    // NetworkManager's cache: instant (0.25 s), but it goes stale.
    function lerRedes()   { exec.connectSource(cmd("--networks" + argTodos)); }
    // A real scan: ~4.5 s. Without it a live network vanishes from the list —
    // one at 80% signal was absent from the cache and returned on scanning.
    function varrerRedes() {
        root.varrendo = true;
        exec.connectSource(cmd("--networks --scan" + argTodos));
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

    // Uma linha por PONTO DE ACESSO:
    //   emuso|pct|dbm|seguranca|salva|geracao|fixado|bssid|ssid
    // O nome vem por último porque é o único campo que pode conter "|".
    function montarRedes(saida) {
        redes.clear();
        if (saida.length === 0)
            return;
        const linhas = saida.split("\n");
        for (let i = 0; i < linhas.length; i++) {
            const c = linhas[i].split("|");
            if (c.length < 9) continue;
            redes.append({
                emUso:     c[0] === "1",
                sinalPct:  parseInt(c[1]) || 0,
                dbm:       parseInt(c[2]) || 0,
                seguranca: c[3],
                salva:     c[4] === "1",
                geracao:   c[5],                  // "4".."7", vazio se desconhecida
                fixado:    c[6] === "1",
                bssid:     c[7],
                nome:      c.slice(8).join("|")
            });
        }
    }

    // Arcos acesos de cada rede da lista, pela potência medida. Os cortes são
    // os da prática: −60 é sinal folgado, −72 ainda serve para vídeo, abaixo
    // disso começa a travar. Nunca zero: rede que aparece na lista existe.
    function arcos(dbm, pct) {
        if (dbm === 0) return pct >= 67 ? 3 : pct >= 40 ? 2 : 1;
        if (dbm >= -60) return 3;
        if (dbm >= -72) return 2;
        return 1;
    }

    // Texto de terceiros indo para uma linha de comando: aspas simples com o
    // apóstrofo escapado. Um SSID pode conter qualquer coisa.
    function aspas(t) {
        return "'" + t.replace(/'/g, "'\\''") + "'";
    }

    // Amarrar a rede a UM rádio. É o caso do repetidor: dois aparelhos
    // anunciando o mesmo nome, e o NetworkManager escolhendo pelo sinal —
    // que nem sempre é onde se quer entrar, por exemplo para configurar o
    // principal de dentro dele.
    function fixarPonto(nome, bssid) {
        root.avisoAcao = i18nd(dom, "Connecting to %1…", nome);
        exec.connectSource(cmd("--connect " + aspas(nome) + " " + bssid));
    }
    // Soltar NÃO reconecta: quem tira a amarra costuma estar de saída do
    // lugar, e reconectar ali desfaria o que acabou de pedir.
    function soltarPonto(nome) {
        exec.connectSource(cmd("--desfixar " + aspas(nome)));
    }

    function conectar(nome, salva) {
        if (salva) {
            root.avisoAcao = i18nd(dom, "Connecting to %1…", nome);
            exec.connectSource(cmd("--connect " + aspas(nome)));
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
    // Amostra só com o balão ABERTO. Duas leituras por segundo de /sys num
    // widget que passa o dia fechado é gasto sem leitor.
    // A leitura de rede também roda com o balão FECHADO, mas devagar: é dela
    // que sai o símbolo da bandeja, e um ícone que só descobre o cabo quando
    // alguém abre o balão está sempre atrasado.
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.lerRede()
    }

    Timer {
        interval: 2000
        running: root.expanded
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource(root.cmd("--taxa"))
    }

    onExpandedChanged: {
        if (root.expanded) {
            // Zera as bases: com a leitura anterior de minutos atrás, a
            // primeira taxa sairia como média do intervalo inteiro.
            root.contadores = ({});
            // Uma consulta externa por abertura, não por leitura.
            root.pediuSaida = ({});
            root.lerRede();
            root.lerRadio();
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

        // Cabo: ícone do TEMA, não desenho nosso. É o mesmo símbolo que o
        // Plasma usa para rede cabeada, já tingido pelo painel.
        Kirigami.Icon {
            anchors.centerIn: parent
            visible: root.modoSimbolo === "cabo"
            source: "network-wired-symbolic"
            width:  Kirigami.Units.iconSizes.roundedIconSize(
                        Math.min(compacto.width, compacto.height))
            height: width
        }

        SimboloWifi {
            anchors.centerIn: parent
            visible: root.modoSimbolo !== "cabo"
            barras: root.barras
            numero: root.numeroGeracao
            modo: root.modoSimbolo
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

        // Larguras fixas das colunas da lista, num lugar só.
        //
        // LIÇÃO CARA, paga com o nome de TODAS as redes sumindo da tela: a
        // coluna elástica não pode pedir `Layout.preferredWidth: 0`. O Qt
        // reparte a sobra entre os itens com `fillWidth` em PROPORÇÃO ao
        // tamanho preferido de cada um — pedindo zero, a fatia é zero, e o
        // nome ficou com largura nenhuma enquanto o resto se acomodava.
        //
        // O que alinha é o contrário: prender cada coluna fixa com mínimo
        // IGUAL ao preferido, e deixar o nome com `fillWidth` e mínimo zero.
        // Assim a variação toda cai num lugar só — o nome, que tem reticências
        // para isso — e as outras colunas começam no mesmo x em toda linha.
        // O leque da lista fica no degrau do meio da escada de ícones. O
        // médio pesava mais que o nome da rede, que é o dado principal; o
        // pequeno levou junto o dígito da geração, que a 16 px deixa de se
        // ler — e um número ilegível é pior que nenhum, porque ocupa espaço
        // fingindo informar. 18 é o degrau entre os dois, e é da escada do
        // tema, não número inventado.
        readonly property int colSimbolo: Kirigami.Units.iconSizes.smallMedium
        readonly property int colPct:     Math.round(Kirigami.Units.gridUnit * 2.6)
        readonly property int colMac:     Math.round(Kirigami.Units.gridUnit * 7.0)

        // implicitWidth/Height, not just the Layout hints. An Item with no
        // implicit size opens the popup at zero by zero: the click works,
        // the state turns expanded, and nothing shows on screen.
        //
        // Duas gridUnits a mais desde que a lista virou tabela: o endereço do
        // rádio tem 17 caracteres que não se abreviam sem perder a serventia.
        implicitWidth:  Kirigami.Units.gridUnit * 34
        implicitHeight: coluna.implicitHeight + Kirigami.Units.largeSpacing * 2

        Layout.minimumWidth:    Kirigami.Units.gridUnit * 22
        Layout.preferredWidth:  Kirigami.Units.gridUnit * 34
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

                Kirigami.Icon {
                    visible: root.modoSimbolo === "cabo"
                    source: "network-wired-symbolic"
                    Layout.preferredWidth:  Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                }

                SimboloWifi {
                    visible: root.modoSimbolo !== "cabo"
                    barras: root.barras
                    numero: root.numeroGeracao
                    modo: root.modoSimbolo
                    tamanho: Kirigami.Units.iconSizes.large
                    Layout.preferredWidth:  implicitWidth
                    Layout.preferredHeight: implicitHeight
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
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
                }

                // ---- coluna da direita: rádio, tráfego e endereços -------
                //
                // À direita e alinhada à direita: números em coluna, com a
                // mesma borda, leem-se de relance. Alinhados à esquerda eles
                // dançavam conforme o comprimento — 9 kB/s e 12,3 MB/s
                // começando em lugares diferentes.
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop | Qt.AlignRight
                    spacing: 0

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: i18nd(root.dom, "Wi-Fi")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                        }

                        PlasmaComponents.Switch {
                            id: chaveRadio
                            checked: root.radioLigado
                            // `onToggled`, não `onCheckedChanged`: este último
                            // dispara também quando a leitura do sistema muda
                            // o estado, e o widget mandaria desligar sozinho.
                            onToggled: root.alternarRadio(checked)
                        }
                    }

                }
            }

            // Uma linha por interface, no mesmo desenho: à esquerda o que
            // descreve o MEIO (canal e largura no wifi, velocidade negociada
            // no cabo), no meio o tráfego vivo, e o endereço encostado à
            // direita. São linhas irmãs porque são o mesmo tipo de fato.
            //
            // Esta linha ocupa a largura INTEIRA da janela. Dentro da coluna
            // de textos, como ficou na primeira tentativa, ela empurrava o
            // interruptor para fora do quadro.
            Repeater {
                model: interfaces

                delegate: RowLayout {
                    id: linha
                    Layout.fillWidth: true
                    // Teto explícito: sem ele o balão cresce para caber a
                    // linha, em vez de a linha caber no balão.
                    Layout.maximumWidth: coluna.width
                    // A dica do gateway saía ATRÁS da linha de cima: irmãos
                    // desenhados depois cobrem os de antes, e a dica nasce
                    // presa a este item. Subindo a linha inteira enquanto o
                    // mouse está nela, a dica passa a ser desenhada por
                    // último e aparece inteira.
                    z: areaDica.containsMouse ? 10 : 0
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: model.tipo === "cabo"
                            ? "network-wired-symbolic"
                            : "network-wireless-symbolic"
                        opacity: 0.7
                        Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }

                    PlasmaComponents.Label {
                        text: model.tipo === "cabo"
                            ? (model.link.length > 0
                                ? i18nd(root.dom, "%1 Mb/s", model.link)
                                : model.dev)
                            : (root.canal.length > 0
                                ? i18nd(root.dom, "Channel %1  ·  %2",
                                        root.canal, root.largura)
                                : model.dev)
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.minimumWidth: 0
                    }

                    PlasmaComponents.Label {
                        text: "↓ " + root.textoTaxa(model.down)
                            + "   ↑ " + root.textoTaxa(model.up)
                        font: Kirigami.Theme.smallFont
                        opacity: 0.85
                        Layout.minimumWidth: 0
                    }

                    // O endereço é o ELÁSTICO da linha: `fillWidth` com
                    // `minimumWidth: 0`. Com um espaçador rígido no lugar
                    // dele, quando a soma passava da janela ninguém cedia e a
                    // linha estourava pela direita — o espaçador some, mas os
                    // rótulos guardam a largura implícita do texto.
                    //
                    // O GATEWAY SAIU DAQUI, para o balão de dica. Medida a
                    // linha, o par ip+gw sozinho ocupava mais que os outros
                    // três blocos somados — e o gateway é o dado mais
                    // repetido da tela: costuma ser o mesmo nas duas
                    // interfaces e quase nunca é consultado.
                    PlasmaComponents.Label {
                        // Sem endereço a linha continua aparecendo, dizendo
                        // isso: um cabo plugado que ainda não pegou IP é
                        // informação, e escondê-lo é responder à pergunta
                        // errada.
                        text: model.ip.length === 0
                            ? i18nd(root.dom, "no address")
                            : i18nd(root.dom, "ip %1", model.ip)
                        horizontalAlignment: Text.AlignRight
                        opacity: 0.65
                        font: Kirigami.Theme.smallFont
                        // Corte pela ESQUERDA: num endereço o fim é o que
                        // identifica — perder "192.168." dói menos que
                        // perder ".96/24".
                        elide: Text.ElideLeft
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        PlasmaComponents.ToolTip.visible: areaDica.containsMouse
                        PlasmaComponents.ToolTip.text:
                            root.dicaInterface(model.dev, model.gw, model.saida)
                        // Clicar copia a linha inteira — endereço, gateway e
                        // IP de saída. É o que se digita em chamado de
                        // suporte, e digitar à mão um IP lido na tela é como
                        // se erra um dígito.
                        MouseArea {
                            id: areaDica
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.copiarEndereco(model.ip, model.gw, model.saida)
                        }
                    }

                    // Abre o formulário de endereço DESTA interface.
                    PlasmaComponents.ToolButton {
                        icon.name: "configure"
                        flat: true
                        implicitWidth: Kirigami.Units.iconSizes.small * 1.6
                        implicitHeight: implicitWidth
                        checked: root.linhaConfig === index
                        onClicked: root.linhaConfig === index
                            ? root.linhaConfig = -1
                            : root.abrirConfig(index, model.dev)
                        PlasmaComponents.ToolTip.visible: hovered
                        PlasmaComponents.ToolTip.text: i18nd(root.dom, "Address settings")
                    }
                }
            }

            // Formulário de endereço, uma linha por vez. Fica FORA do
            // Repeater das linhas: dentro dele, cada delegate teria o seu, e
            // a janela cresceria com formulários invisíveis empilhados.
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.linhaConfig >= 0
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: i18nd(root.dom, "Address of %1 (%2)", root.cfgDev, root.cfgPerfil)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    PlasmaComponents.RadioButton {
                        text: i18nd(root.dom, "DHCP")
                        checked: root.cfgMetodo === "auto"
                        onToggled: if (checked) root.cfgMetodo = "auto"
                    }
                    PlasmaComponents.RadioButton {
                        text: i18nd(root.dom, "Manual")
                        checked: root.cfgMetodo === "manual"
                        onToggled: if (checked) root.cfgMetodo = "manual"
                    }
                    // PPPoE só aparece se JÁ existir um perfil desse tipo.
                    // Criar um pediria usuário e senha nesta tela, e a senha
                    // iria por linha de comando, onde qualquer processo a lê.
                    PlasmaComponents.RadioButton {
                        visible: root.cfgPppoe.length > 0
                        text: i18nd(root.dom, "PPPoE")
                        checked: root.cfgMetodo === "pppoe"
                        onToggled: if (checked) root.cfgMetodo = "pppoe"
                    }
                    Item { Layout.fillWidth: true }
                }

                // O QUE O DHCP ENTREGOU, em três leituras lado a lado.
                //
                // Isto substituiu uma ficha com o selo "dhcp" ao lado do
                // número. O selo era enfeite: dizia de onde veio o endereço
                // e nada mais, no meio de fichas que se apagam com um "×"
                // que ali não existia. Três colunas rotuladas respondem a
                // pergunta inteira — quem sou eu aqui dentro, por onde eu
                // saio, e com que cara eu apareço lá fora.
                //
                // Só aparece quando HÁ endereço automático. Sem DHCP não há
                // linha nenhuma: uma linha de rótulos com traços é ruído.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.cfgIpAuto.length > 0
                    spacing: 0

                    PlasmaComponents.Label {
                        text: i18nd(root.dom, "Received automatically (DHCP)")
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing / 2
                        radius: Kirigami.Units.cornerRadius
                        // A cor da tinta com alfa, NÃO `opacity` no retângulo:
                        // opacidade no pai apaga o filho junto, e foi assim
                        // que o endereço do DHCP virou cinza sobre cinza —
                        // ilegível numa tela clara.
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
                        implicitHeight: leitura.implicitHeight + Kirigami.Units.smallSpacing * 2

                        RowLayout {
                            id: leitura
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                // Rótulos em palavra de gente, valor embaixo:
                                // "gateway" e "IP de saída" são jargão, e o
                                // widget é lido por quem só quer saber se a
                                // internet está de pé.
                                model: [
                                    { rot: i18nd(root.dom, "This machine"),
                                      val: root.cfgIpAuto },
                                    { rot: i18nd(root.dom, "Gateway (router)"),
                                      val: root.gatewayDe(root.cfgDev) },
                                    { rot: i18nd(root.dom, "Out on the internet"),
                                      val: root.cfgSaidaPerguntada && root.cfgSaida.length === 0
                                           ? "…"
                                           : root.cfgSaida }
                                ]

                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    Kirigami.Separator {
                                        visible: index > 0
                                        Layout.fillHeight: true
                                        Layout.preferredWidth: 1
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 0

                                        PlasmaComponents.Label {
                                            text: modelData.rot
                                            font: Kirigami.Theme.smallFont
                                            opacity: 0.6
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        PlasmaComponents.Label {
                                            // Sem opacidade: este é o número
                                            // que se veio ler.
                                            text: modelData.val.length > 0
                                                  ? modelData.val
                                                  : i18nd(root.dom, "none")
                                            font: Kirigami.Theme.smallFont
                                            opacity: modelData.val.length > 0 ? 1.0 : 0.45
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Endereços FIXOS, como fichas. Cada uma está escrita no
                // perfil e sai com o "×".
                //
                // Aqui a ação é IMEDIATA: adicionar e remover valem na hora,
                // sem passar pelo Aplicar. Um botão que guarda mudanças de
                // lista para depois obriga a lembrar o que se pediu.
                PlasmaComponents.Label {
                    visible: enderecos.count > 0
                    text: i18nd(root.dom, "Fixed addresses")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    Layout.topMargin: Kirigami.Units.smallSpacing / 2
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: enderecos
                        delegate: Rectangle {
                            radius: height / 2
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.10)
                            border.width: 1
                            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.22)
                            implicitWidth: fichaLinha.implicitWidth + Kirigami.Units.largeSpacing
                            implicitHeight: fichaLinha.implicitHeight + Kirigami.Units.smallSpacing

                            RowLayout {
                                id: fichaLinha
                                anchors.centerIn: parent
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: model.texto
                                    font: Kirigami.Theme.smallFont
                                }
                                PlasmaComponents.ToolButton {
                                    icon.name: "edit-delete-remove"
                                    flat: true
                                    implicitWidth: Kirigami.Units.iconSizes.small * 1.2
                                    implicitHeight: implicitWidth
                                    onClicked: root.removerEndereco(model.texto)
                                    PlasmaComponents.ToolTip.visible: hovered
                                    PlasmaComponents.ToolTip.text: i18nd(root.dom, "Remove this address")
                                }
                            }
                        }
                    }
                }

                // Acrescentar um endereço. O "sugerir" varre de .240 para
                // baixo — faixa que quase nunca está no poço do DHCP — e só
                // devolve quem não responder a ping.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.TextField {
                        text: root.cfgNovo
                        placeholderText: i18nd(root.dom, "another address, e.g. 192.168.1.240/24")
                        onTextChanged: root.cfgNovo = text
                        onAccepted: root.adicionarEndereco()
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }
                    PlasmaComponents.ToolButton {
                        icon.name: "games-solve"
                        flat: true
                        onClicked: root.sugerirEndereco()
                        PlasmaComponents.ToolTip.visible: hovered
                        PlasmaComponents.ToolTip.text: i18nd(root.dom, "Suggest a free address")
                    }
                    PlasmaComponents.ToolButton {
                        icon.name: "list-add"
                        flat: true
                        onClicked: root.adicionarEndereco()
                        PlasmaComponents.ToolTip.visible: hovered
                        PlasmaComponents.ToolTip.text: i18nd(root.dom, "Add address")
                    }
                }

                GridLayout {
                    visible: root.cfgMetodo === "manual"
                    columns: 2
                    columnSpacing: Kirigami.Units.smallSpacing
                    rowSpacing: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        text: i18nd(root.dom, "Gateway")
                        font: Kirigami.Theme.smallFont
                    }
                    PlasmaComponents.TextField {
                        text: root.cfgGateway
                        placeholderText: "192.168.1.1"
                        onTextChanged: root.cfgGateway = text
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: i18nd(root.dom, "DNS")
                        font: Kirigami.Theme.smallFont
                    }
                    PlasmaComponents.TextField {
                        text: root.cfgDns
                        placeholderText: "1.1.1.1"
                        onTextChanged: root.cfgDns = text
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Button {
                        text: i18nd(root.dom, "Cancel")
                        flat: true
                        onClicked: root.linhaConfig = -1
                    }
                    PlasmaComponents.Button {
                        text: i18nd(root.dom, "Apply")
                        icon.name: "dialog-ok-apply"
                        onClicked: root.aplicarConfig()
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
                    //
                    // Rede e ponto de acesso são coisas diferentes, e a
                    // contagem tem de dizer qual das duas está contando:
                    // "6 redes" onde três linhas têm o mesmo nome faria o
                    // dono achar que tem seis vizinhos.
                    text: root.mostrarTodos
                        ? i18ndp(root.dom, "%1 access point nearby",
                                 "%1 access points nearby", redes.count)
                        : i18ndp(root.dom, "%1 network nearby",
                                 "%1 networks nearby", redes.count)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    Layout.fillWidth: true
                }

                // "Varrendo…" ocupa lugar SEMPRE, aceso ou apagado. Com
                // `visible`, a palavra nascia e morria a cada varredura e
                // empurrava os dois botões para os lados — botão que se mexe
                // é botão em que se erra o clique.
                PlasmaComponents.Label {
                    opacity: root.varrendo ? 0.6 : 0.0
                    text: i18nd(root.dom, "scanning…")
                    font: Kirigami.Theme.smallFont
                }

                // Ver cada aparelho separadamente. Ao lado da varredura porque
                // é a mesma pergunta feita com outra lente, e porque quem liga
                // isto quase sempre varre em seguida.
                PlasmaComponents.ToolButton {
                    icon.name: "view-list-details"
                    checkable: true
                    checked: root.mostrarTodos
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18nd(root.dom, "Show routers and repeaters")
                    onToggled: {
                        root.mostrarTodos = checked;
                        root.lerRedes();      // cache: a lista muda na hora
                        root.varrerRedes();   // e a varredura confirma
                    }
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.text: i18nd(root.dom, "Show routers and repeaters")
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh-symbolic"
                    enabled: !root.varrendo
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18nd(root.dom, "Scan again")
                    onClicked: root.varrerRedes()
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.text: i18nd(root.dom, "Scan again")
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

                    // Quatro colunas, e só o NOME é elástico. As demais têm
                    // mínimo igual ao preferido, então começam sempre no mesmo
                    // x; a variação de comprimento cai toda no nome, que tem
                    // reticências justamente para isso.
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: model.nome
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            font.bold: model.emUso
                        }

                        // O endereço do rádio aparece SÓ no modo que mostra
                        // roteadores e repetidores. Fora dele, cada linha tem
                        // um nome diferente e o endereço é ruído; dentro dele,
                        // é a única coisa que distingue três linhas chamadas
                        // "wifi_zone" — e é a quem a caixinha se refere.
                        PlasmaComponents.Label {
                            visible: root.mostrarTodos
                            text: model.bssid
                            font: Kirigami.Theme.smallFont
                            opacity: 0.45
                            elide: Text.ElideRight
                            Layout.preferredWidth: janela.colMac
                            Layout.minimumWidth: janela.colMac
                            Layout.maximumWidth: janela.colMac
                        }

                        // O MESMO símbolo da bandeja: leque com o número da
                        // geração dentro. Antes eram duas colunas — endereço e
                        // "Wi-Fi 6" escrito — para dizer o que este desenho já
                        // diz num quadrado, e que o dono da máquina lê todo dia
                        // no relógio. Um símbolo aprendido uma vez vale mais
                        // que duas colunas de texto.
                        SimboloWifi {
                            barras: root.arcos(model.dbm, model.sinalPct)
                            numero: model.geracao
                            tamanho: janela.colSimbolo
                            Layout.preferredWidth:  janela.colSimbolo
                            Layout.minimumWidth:    janela.colSimbolo
                            Layout.maximumWidth:    janela.colSimbolo
                            Layout.preferredHeight: janela.colSimbolo

                            PlasmaComponents.ToolTip.visible: areaGer.containsMouse
                            PlasmaComponents.ToolTip.text:
                                (model.geracao.length > 0
                                    ? i18nd(root.dom, "Wi-Fi %1", model.geracao) + "  ·  "
                                    : "")
                                + model.bssid + "  ·  " + model.dbm + " dBm"
                            MouseArea {
                                id: areaGer
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }

                        PlasmaComponents.Label {
                            // Percentual não passa por catálogo: "%1%" fazia o gettext desconfiar
                            // do "%" final e rebaixar a tradução a fuzzy — e fuzzy fica em inglês.
                            text: model.sinalPct + "%"
                            opacity: 0.6
                            font: Kirigami.Theme.smallFont
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: janela.colPct
                            Layout.minimumWidth:   janela.colPct
                            Layout.maximumWidth:   janela.colPct
                        }

                        // "Conectar só neste roteador."
                        //
                        // Numa casa com repetidor, o NetworkManager entra
                        // pelo sinal mais forte — que é o repetidor, e não o
                        // aparelho principal onde mora a configuração. Marcar
                        // aqui amarra o perfil a este rádio e sobe a conexão;
                        // desmarcar solta, sem reconectar.
                        //
                        // Desabilitada em rede não salva: a amarra se escreve
                        // no perfil, e perfil ainda não existe. Fica visível
                        // mesmo assim, para a coluna não dançar de linha em
                        // linha.
                        PlasmaComponents.CheckBox {
                            checked: model.fixado
                            enabled: model.salva
                            opacity: model.salva ? 1.0 : 0.3
                            onToggled: checked
                                ? root.fixarPonto(model.nome, model.bssid)
                                : root.soltarPonto(model.nome)
                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.text: model.salva
                                ? i18nd(root.dom, "Connect only to this router")
                                : i18nd(root.dom, "Save the network first")
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

            // A legenda ensina os três símbolos da lista, em três frases
            // curtas. Ícone que precisa de explicação ou ganha legenda, ou
            // vira adivinhação — e quem usa este widget nem sempre é quem o
            // escreveu.
            PlasmaComponents.Label {
                text: i18nd(root.dom, "Number in the fan: Wi-Fi generation.")
                    + "  " + i18nd(root.dom, "Dimmed padlock: network not saved.")
                    + "  " + i18nd(root.dom, "Checkbox: stay on this router.")
                font: Kirigami.Theme.smallFont
                opacity: 0.5
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }
        }
    }
}
