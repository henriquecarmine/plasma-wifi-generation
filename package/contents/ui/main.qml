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
import org.kde.plasma.core as PlasmaCore
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

    // ---- em QUE RÁDIO estamos, e se podemos sair dele ------------------
    //
    // "Conectado ao wifi_zone_5G" não distingue o roteador da sala do
    // repetidor da varanda. É uma distinção cara: um repetidor que faz NAT
    // sobre NAT põe o computador numa sub-rede própria, e o telefone da casa,
    // que ficou na outra, deixa de ser alcançável. Quem não vê em qual rádio
    // entrou passa a tarde procurando o defeito no lugar errado.
    property string bssidAtual:  ""   // o rádio em que estamos, agora
    property string fixadoEm:    ""   // rádio a que o perfil ATIVO está amarrado
    property string perfilAtual: ""
    property string preferido:   ""   // rádio marcado com a estrela, deste SSID
    property int    perfisDaRede: 0   // quantos perfis salvos disputam este nome

    // ---- preferência de rádio, com histerese ---------------------------
    property int    roamCorte:  -80
    property int    roamMargem: 6
    property bool   roamAuto:   false
    property string roamAcao:   "nada"
    property string roamPrefDbm: ""
    // Quando o automático agiu pela última vez. Reconectar a rede é operação
    // de segundos, e sem esta trava a leitura seguinte — que chega antes de a
    // associação terminar — mandaria reconectar de novo, em laço.
    property double ultimaTroca: 0

    // ---- qualidade MEDIDA, por rádio -----------------------------------
    //
    // dBm mede a antena; isto mede a saída. Um repetidor a 700 Mb/s de taxa
    // negociada que entrega 5 Mb/s de internet ganha de longe no dBm e perde
    // feio aqui — e é aqui que a pergunta real é feita.
    property var    medidas: ({})     // bssid -> {nat, rtt, jit, perda, pico, am, nota}
    property int    notaAtual:   -1
    property string melhorBssid: ""
    property int    melhorNota:  -1
    property bool   testando:    false

    // Pico de vazão REAL desta passagem pelo rádio. Sai de graça dos
    // contadores que o widget já lê a cada 2 s para desenhar as setinhas:
    // mede o que a pessoa de fato conseguiu passar, não o que o rádio promete.
    property double picoSessao:     0
    property double picoGravado:    0
    property double ultimoEnvioPico: 0

    function notaDe(bssid) {
        const q = root.medidas[(bssid || "").toLowerCase()];
        return (q && q.am > 0) ? q.nota : -1;
    }

    // `comNota` porque o mesmo resumo serve em dois lugares: na dica da
    // lista, onde a nota precisa vir junto, e na caixa do balão, onde ela já
    // está em negrito ao lado — e repeti-la lia como gagueira.
    function resumoQualidade(bssid, comNota) {
        const q = root.medidas[(bssid || "").toLowerCase()];
        if (!q || q.am <= 0) return i18nd(dom, "not measured yet");
        let t = comNota ? i18nd(dom, "score %1", q.nota) + "  ·  " : "";
        t += (q.nat > 1 ? i18nd(dom, "%1 NATs", q.nat)
                        : i18nd(dom, "1 NAT"));
        t += "  ·  " + Math.round(q.rtt) + " ms";
        if (q.jit > 0) t += " ±" + q.jit.toFixed(1);
        if (q.perda > 0) t += "  ·  " + q.perda + "%";
        if (q.pico > 0)  t += "  ·  " + root.textoTaxa(q.pico);
        return t;
    }

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

    // A segurança vem do RÁDIO, não do nome da rede: numa casa onde o
    // roteador principal fala WPA3 e o repetidor só fala WPA2, dizer "WPA2
    // WPA3" para os dois apaga a diferença que faz a senha ser pedida de novo
    // ao trocar de sala.
    function textoSeguranca(s) {
        switch (s) {
        case "open":    return i18nd(dom, "open");
        case "owe":     return i18nd(dom, "open (encrypted)");
        case "wep":     return "WEP";
        case "psk":     return "WPA2";
        // Modo misto: o rádio ainda aceita WPA1/TKIP. Dizer só "WPA2"
        // esconderia o que a coluna de segurança existe para mostrar.
        case "psk-wpa1": return "WPA/WPA2";
        case "sae":     return "WPA3";
        case "psk-sae": return "WPA2/WPA3";
        case "eap":     return i18nd(dom, "enterprise");
        default:        return i18nd(dom, "unknown");
        }
    }

    // Rede sem senha é rede sem senha, e o cadeado tem de dizer isso — ABERTO.
    // "owe" também entra aqui: o tráfego é cifrado, mas ninguém digita nada
    // para entrar, e é essa a pergunta que o cadeado responde.
    function semSenha(s) {
        return s === "open" || s === "owe";
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
                "ip": c[2] || "", "gw": c[3] || "", "link": c[4] || "",
                // A interface da ROTA PADRÃO — por onde o pacote realmente
                // sai. Ter gateway não é sair por ele: com cabo e wifi
                // ligados os dois têm gateway e só um leva o tráfego.
                "padrao": c[5] === "1"
            };
            // Atualizar em vez de recriar: recriando, as taxas piscavam a
            // cada leitura de endereço, porque a linha nascia zerada.
            if (achou >= 0) {
                interfaces.setProperty(achou, "tipo", dados.tipo);
                interfaces.setProperty(achou, "ip",   dados.ip);
                interfaces.setProperty(achou, "gw",   dados.gw);
                interfaces.setProperty(achou, "link", dados.link);
                interfaces.setProperty(achou, "padrao", dados.padrao);
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
                    const baixada = dr >= 0 ? dr / dt : 0;
                    interfaces.setProperty(j, "down", baixada);
                    interfaces.setProperty(j, "up",   dtx >= 0 ? dtx / dt : 0);
                    // Vazão REAL do rádio em que estamos, sem gerar um byte
                    // de tráfego: é o maior valor que o uso normal alcançou.
                    // Só conta a sem fio — a taxa do cabo não diz nada sobre
                    // o rádio, e somá-la ali daria nota alta ao pior deles.
                    if (interfaces.get(j).tipo === "wifi"
                            && root.bssidAtual.length > 0
                            && baixada > root.picoSessao)
                        root.picoSessao = baixada;
                }
            }
            root.contadores[dev] = { "rx": rx, "tx": tx, "ms": agora };
        }
        // Grava com parcimônia: só quando o pico cresceu de verdade (10%) e
        // no máximo a cada 30 s. Sem as duas travas, uma transferência longa
        // chamaria o script a cada dois segundos para gravar o mesmo número.
        if (root.bssidAtual.length > 0
                && root.picoSessao > root.picoGravado * 1.1
                && agora - root.ultimoEnvioPico > 30000) {
            root.picoGravado = root.picoSessao;
            root.ultimoEnvioPico = agora;
            exec.connectSource(root.cmd("--pico " + root.bssidAtual
                                        + " " + Math.round(root.picoSessao)));
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

    // Qual símbolo a bandeja mostra: o do meio por onde a internet SAI.
    //
    // Quem decide é a rota padrão, não a existência de gateway. Cabo plugado
    // com wifi ligado dá dois gateways, e só um leva o tráfego — o do cabo,
    // que o NetworkManager põe com métrica melhor. Mostrar o leque ali é
    // dizer que a máquina está no ar pelo wifi quando não está.
    //
    // ANTES havia um terceiro modo, "mix": o leque com um pontinho no canto,
    // para quando os dois enlaces tinham gateways distintos. Saiu a pedido do
    // dono, e com razão — o ponto não dizia coisa nenhuma a quem não tivesse
    // lido o código que o desenhou, e a pergunta que se faz olhando a bandeja
    // é "estou no cabo ou no wifi?", que ele não respondia. Os dois enlaces
    // continuam listados dentro do balão, cada um com o seu endereço.
    readonly property string modoSimbolo: {
        let cabo = false, wifi = false;
        for (let i = 0; i < interfaces.count; i++) {
            const it = interfaces.get(i);
            if (it.padrao) {
                if (it.tipo === "cabo") return "cabo";
                return "wifi";
            }
            if (it.gw && it.gw.length > 0) {
                if (it.tipo === "cabo") cabo = true; else wifi = true;
            }
        }
        // Sem rota padrão ainda — cabo recém-plugado, por exemplo. O cabo
        // ganha assim mesmo: quem acabou de plugá-lo está olhando para ele.
        if (cabo) return "cabo";
        return "wifi";
    }

    // A dica da bandeja precisa dizer o que o símbolo não cabe dizer: qual é
    // o OUTRO enlace, quando há dois. Sem isso, trocar o leque pelo cabo
    // esconderia o wifi por completo de quem só olha o ícone.
    readonly property string outroEnlace: {
        for (let i = 0; i < interfaces.count; i++) {
            const it = interfaces.get(i);
            if (it.padrao) continue;
            if (!it.gw || it.gw.length === 0) continue;
            return it.tipo === "cabo"
                ? i18nd(dom, "cable also connected (%1)", it.ip)
                : i18nd(dom, "Wi-Fi also connected (%1)", it.ip);
        }
        return "";
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
            } else if (source.indexOf(" --perfil ") >= 0) {
                // O espaço dos DOIS lados não é enfeite: "--perfil" casa
                // dentro de "--perfis" e dentro de "--apagar-perfil", e a
                // resposta de um ia parar no despachante do outro.
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
            } else if (source.indexOf("--qualidade") >= 0) {
                root.montarQualidade(saida);
            } else if (source.indexOf("--medir") >= 0) {
                // A medição só grava; quem lê de volta é o --qualidade.
                exec.connectSource(cmd("--qualidade"));
            } else if (source.indexOf("--teste") >= 0) {
                root.testando = false;
                const c = saida.split("|");
                root.avisoAcao = c[0] === "OK"
                    ? i18nd(root.dom, "Measured: %1", root.textoTaxa(parseFloat(c[2]) || 0))
                    : i18nd(root.dom, "Could not measure throughput.");
                exec.connectSource(cmd("--qualidade"));
            } else if (source.indexOf("--pico") >= 0) {
                // Sem resposta na tela: é registro de fundo, não ação de ninguém.
            } else if (source.indexOf("--roaming") >= 0) {
                root.aplicarRoaming(saida);
            } else if (source.indexOf("--limiar") >= 0) {
                const c = saida.split("|");
                root.roamCorte  = parseInt(c[0]) || -80;
                root.roamMargem = parseInt(c[1]) || 6;
                root.roamAuto   = c[2] === "1";
            } else if (source.indexOf(" --perfis ") >= 0) {
                root.montarPerfis(saida);
            } else if (source.indexOf("--preferir") >= 0
                    || source.indexOf("--despreferir") >= 0) {
                root.lerEstado();
                root.lerRedes();
                root.lerRoaming();
            } else if (source.indexOf("--apagar-perfil") >= 0) {
                root.avisoAcao = saida.indexOf("OK|") === 0
                    ? i18nd(root.dom, "Extra profile removed.")
                    : i18nd(root.dom, "Could not remove that profile.");
                root.lerEstado();
                if (root.ssid.length > 0)
                    exec.connectSource(cmd("--perfis " + aspas(root.ssid)));
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
    function lerRoaming() { exec.connectSource(cmd("--roaming")); }
    function lerPerfis()  {
        if (root.ssid.length > 0)
            exec.connectSource(cmd("--perfis " + aspas(root.ssid)));
    }

    // ---- preferência de rádio -----------------------------------------
    //
    // A estrela marca QUAL rádio se quer usar; o corte diz até que ponto ele
    // ainda serve. Enquanto o preferido estiver acima do corte, é nele que se
    // fica; abaixo, a amarra sai e o sistema volta a escolher sozinho.
    //
    // É o conserto do repetidor mal colocado: ele chega mais forte em quase
    // toda a casa, o NetworkManager escolhe por potência e entra sempre nele,
    // e como ele faz NAT sobre NAT o computador perde de vista o telefone que
    // está na mesma casa. Potência não é qualidade — a preferência é o lugar
    // onde essa diferença cabe.
    function preferirPonto(nome, bssid) {
        exec.connectSource(cmd("--preferir " + aspas(nome) + " " + bssid));
    }
    function despreferirPonto(nome) {
        exec.connectSource(cmd("--despreferir " + aspas(nome)));
    }
    function ajustarLimiar(chave, valor) {
        exec.connectSource(cmd("--limiar " + chave + " " + valor));
    }

    // O conselho do script, e o que fazer com ele.
    //
    // Agir é OPCIONAL e vem desligado: reconectar a rede de alguém sem que
    // essa pessoa tenha pedido é o tipo de esperteza que se paga caro — no
    // meio de uma chamada de vídeo, por exemplo. Ligado, respeita a trava de
    // trinta segundos: a associação leva alguns, e a leitura seguinte chega
    // antes dela terminar.
    function aplicarRoaming(saida) {
        const c = saida.split("|");
        if (c.length < 10) return;
        root.roamAuto    = c[0] === "1";
        root.roamCorte   = parseInt(c[1]) || -80;
        root.roamMargem  = parseInt(c[2]) || 6;
        root.preferido   = c[4] || "";
        root.roamPrefDbm = c[5] || "";
        root.roamAcao    = c[9] || "nada";
        root.notaAtual   = c.length > 10 && c[10].length > 0 ? parseInt(c[10]) : -1;
        root.melhorBssid = c.length > 11 ? (c[11] || "") : "";
        root.melhorNota  = c.length > 12 && c[12].length > 0 ? parseInt(c[12]) : -1;

        if (!root.roamAuto || root.roamAcao === "nada") return;
        const agora = Date.now();
        if (agora - root.ultimaTroca < 30000) return;
        root.ultimaTroca = agora;
        const rede = c[3] || "";
        if (rede.length === 0) return;
        if (root.roamAcao === "fixar") {
            root.avisoAcao = i18nd(dom, "Going back to the preferred router…");
            exec.connectSource(cmd("--connect " + aspas(rede) + " " + root.preferido));
        } else if (root.roamAcao === "soltar") {
            root.avisoAcao = i18nd(dom, "Preferred below %1 dBm — roaming.",
                                   root.roamCorte);
            exec.connectSource(cmd("--desfixar " + aspas(rede)));
        } else if (root.roamAcao === "trocar") {
            root.avisoAcao = i18nd(dom, "Better router measured — switching.");
            exec.connectSource(cmd("--connect " + aspas(rede) + " " + root.melhorBssid));
        }
    }

    function apagarPerfil(uuid) {
        exec.connectSource(cmd("--apagar-perfil " + uuid));
    }

    // "bssid|nat|rtt|jitter|perda|pico|amostras|nota"
    function montarQualidade(saida) {
        const m = {};
        const linhas = saida.split("\n");
        for (let i = 0; i < linhas.length; i++) {
            const c = linhas[i].split("|");
            if (c.length < 8) continue;
            m[c[0].toLowerCase()] = {
                nat:   parseInt(c[1]) || 1,
                rtt:   parseFloat(c[2]) || 0,
                jit:   parseFloat(c[3]) || 0,
                perda: parseFloat(c[4]) || 0,
                pico:  parseFloat(c[5]) || 0,
                am:    parseInt(c[6]) || 0,
                nota:  parseInt(c[7]) || 0
            };
        }
        root.medidas = m;
        // A nota mora TAMBÉM na linha da lista: um ListModel não reavalia
        // ligações quando um mapa externo muda, então a medida que chega
        // depois da lista não apareceria em linha nenhuma.
        for (let j = 0; j < redes.count; j++)
            redes.setProperty(j, "nota", root.notaDe(redes.get(j).bssid));
    }

    // Medir é de graça em interrupção: roda DEPOIS de a conexão já ter
    // subido. O script recusa refazer medida com menos de dez minutos, senão
    // uma reconexão em rajada — queda de sinal — viraria uma medição atrás
    // da outra, e o widget seria a causa do tráfego que diz medir.
    function medirRadio(forcar) {
        exec.connectSource(cmd("--medir" + (forcar ? " --forcar" : "")));
    }
    function testarVazao() {
        root.testando = true;
        root.avisoAcao = i18nd(dom, "Measuring throughput…");
        exec.connectSource(cmd("--teste"));
    }

    onBssidAtualChanged: {
        if (root.bssidAtual.length === 0) return;
        // Rádio novo, medida nova, e o pico recomeça: o pico é DESTE rádio.
        root.picoSessao = 0;
        root.picoGravado = 0;
        root.medirRadio(false);
    }
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
        // Os cinco últimos são recentes e chegam com `|| ""`: um pacote
        // atualizado pela metade — script novo, QML velho, ou o contrário —
        // deve degradar, não quebrar a tela inteira.
        root.bssidAtual    = campos[10] || "";
        root.fixadoEm      = campos[11] || "";
        root.perfilAtual   = campos[12] || "";
        root.preferido     = campos[13] || "";
        root.perfisDaRede  = parseInt(campos[14]) || 0;
    }

    // ---- em que rádio estamos, dito em uma frase -----------------------
    //
    // Três estados, e a diferença entre eles é o que o dono desta máquina
    // passou uma tarde tentando descobrir olhando a tela: preso a um rádio,
    // livre para trocar, ou livre mas com um preferido esperando sinal.
    readonly property string modoRadio: {
        if (!conectado) return "";
        if (fixadoEm.length > 0) return "fixo";
        if (preferido.length > 0) return "preferido";
        return "roaming";
    }

    readonly property string textoModoRadio: {
        switch (modoRadio) {
        case "fixo":
            return i18nd(dom, "Locked to this router");
        case "preferido":
            // Curtos de propósito: a linha já carrega o MAC, que tem
            // dezessete caracteres, e o que sobra é pouco. Frase que não cabe
            // vira reticências, e reticências não dizem nada.
            return bssidAtual === preferido
                ? i18nd(dom, "on the preferred router")
                : i18nd(dom, "roaming — preferred out of reach");
        case "roaming":
            return i18nd(dom, "roaming freely");
        default:
            return "";
        }
    }

    readonly property string iconeModoRadio:
        modoRadio === "fixo" ? "pin-symbolic"
        : (modoRadio === "preferido" && bssidAtual === preferido) ? "favorite"
        : "network-wireless-symbolic"

    // Uma linha por PONTO DE ACESSO:
    //   emuso|pct|dbm|seguranca|salva|geracao|fixado|preferido|bssid|ssid
    // O nome vem por último porque é o único campo que pode conter "|".
    function montarRedes(saida) {
        redes.clear();
        if (saida.length === 0)
            return;
        const linhas = saida.split("\n");
        for (let i = 0; i < linhas.length; i++) {
            const c = linhas[i].split("|");
            if (c.length < 10) continue;
            redes.append({
                emUso:     c[0] === "1",
                sinalPct:  parseInt(c[1]) || 0,
                dbm:       parseInt(c[2]) || 0,
                seguranca: c[3],
                salva:     c[4] === "1",
                geracao:   c[5],                  // "4".."7", vazio se desconhecida
                fixado:    c[6] === "1",
                preferido: c[7] === "1",
                bssid:     c[8],
                nota:      root.notaDe(c[8]),
                nome:      c.slice(9).join("|")
            });
        }
    }

    // Perfis salvos que disputam o nome da rede atual. Mais de um não é
    // curiosidade de administrador: é a explicação de por que a senha é
    // pedida de novo numa rede salva, e a tela precisa poder dizê-la.
    ListModel { id: perfis }

    function montarPerfis(saida) {
        perfis.clear();
        const linhas = saida.split("\n");
        for (let i = 0; i < linhas.length; i++) {
            const c = linhas[i].split("|");
            if (c.length < 6) continue;
            perfis.append({
                uuid:   c[0],
                nome:   c[1],
                cripto: c[2],
                fixo:   c[3],
                ativo:  c[5] === "1"
            });
        }
    }
    property bool mostrarPerfis: false

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

    // ---- menu do botão direito ----------------------------------------
    //
    // "Configurar Wi-Fi Generation…", que o Plasma põe sozinho, abre a
    // janela de ajustes DO WIDGET — que não tem ajuste nenhum, e portanto
    // mostra só a aba "Sobre". Quem clica ali quer as configurações de rede
    // DA MÁQUINA, então é isso que o menu passa a oferecer: o módulo do
    // NetworkManager, o mesmo que a bandeja de rede do Plasma abre.
    //
    // A entrada interna é escondida em vez de deixada ao lado: duas linhas
    // parecidas no mesmo menu, uma útil e outra que só mostra a versão, é
    // convite a errar o clique todo dia.
    Component.onCompleted: {
        // Guardado por `typeof`: `internalAction` é API do Plasma 6, e num
        // Plasma que não a tenha a chamada lançaria antes do `if` — levando
        // junto todo o resto deste bloco. Esconder um item de menu não vale
        // uma tela em branco.
        if (typeof Plasmoid.internalAction === "function") {
            const interna = Plasmoid.internalAction("configure");
            if (interna) interna.visible = false;
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nd(root.dom, "Wi-Fi and network settings…")
            icon.name: "configure"
            onTriggered: exec.connectSource("kcmshell6 kcm_networkmanagement")
        },
        PlasmaCore.Action {
            text: i18nd(root.dom, "Scan again")
            icon.name: "view-refresh-symbolic"
            onTriggered: root.varrerRedes()
        }
    ]

    Timer {
        interval: 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.lerEstado();
            // O roaming é vigiado com o balão FECHADO também: o preferido
            // volta ao alcance quando a pessoa anda pela casa, não quando ela
            // abre o widget. Vigiar só com o balão aberto seria um automático
            // que só age enquanto alguém olha.
            root.lerRoaming();
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
            root.mostrarPerfis = false;
            root.lerRoaming();
            root.lerPerfis();
            root.lerRedes();     // cache: the list shows at once
            root.varrerRedes();  // scan: replaces it in ~4 s
        }
    }

    toolTipMainText: conectado
        ? (textoGeracao(geracao) + " · " + ssid)
        : estado
    // A dica carrega o que o símbolo não cabe dizer: em qual RÁDIO se está,
    // se dá para sair dele, e qual é o outro enlace quando há dois. Trocar o
    // leque pelo cabo, sem isso, esconderia o wifi de quem só olha o ícone.
    toolTipSubText: {
        if (!conectado) return outroEnlace;
        let t = i18nd(dom, "%1/%2 Mb/s  ·  %3 dBm (%4)",
                      rx, tx, sinal, textoQualidade(qualidade));
        if (bssidAtual.length > 0)
            t += "\n" + bssidAtual + "  ·  " + textoModoRadio;
        if (outroEnlace.length > 0)
            t += "\n" + outroEnlace;
        return t;
    }

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

                    // ---- EM QUAL RÁDIO, e se dá para sair dele ---------
                    //
                    // A linha mais pedida deste widget. O nome da rede não
                    // distingue o roteador da sala do repetidor da varanda,
                    // e é essa distinção que decide se o computador enxerga
                    // o telefone da casa — um repetidor que faz NAT sobre
                    // NAT põe os dois em sub-redes diferentes.
                    //
                    // O ícone à esquerda separa fixo de roaming de relance:
                    // alfinete é amarra, estrela é o preferido, leque é
                    // livre. A palavra ao lado diz a mesma coisa por
                    // extenso, porque ícone sozinho é adivinhação.
                    RowLayout {
                        visible: root.conectado && root.bssidAtual.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing / 2
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: root.iconeModoRadio
                            opacity: 0.7
                            Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }

                        PlasmaComponents.Label {
                            text: root.bssidAtual + "  ·  " + root.textoModoRadio
                            opacity: 0.7
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                        }
                    }
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

            // ---- a QUALIDADE MEDIDA deste rádio ---------------------------
            //
            // A caixa que responde "que adianta conectar a 700 Mb/s e sair
            // com cinco megas?". Nenhum número aqui vem do dBm: são saltos
            // de NAT, ida e volta até a internet, jitter, perda e a maior
            // vazão que o uso real já alcançou neste rádio.
            //
            // A medição roda sozinha ao entrar num rádio — depois de a
            // conexão já ter subido, que é quando não custa interrupção
            // nenhuma. O teste de vazão fica atrás de um botão porque GASTA
            // DADO, e um widget que baixa dez megabytes por conta própria
            // numa conexão limitada é um defeito, não um recurso.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: root.conectado && root.bssidAtual.length > 0
                radius: Kirigami.Units.cornerRadius
                color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
                implicitHeight: caixaQual.implicitHeight + Kirigami.Units.smallSpacing * 2

                ColumnLayout {
                    id: caixaQual
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing / 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: root.notaAtual >= 0
                                ? i18nd(root.dom, "Measured: %1", root.notaAtual)
                                : i18nd(root.dom, "Measuring…")
                            font.bold: true
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                        PlasmaComponents.Label {
                            text: root.resumoQualidade(root.bssidAtual, false)
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                        }
                        PlasmaComponents.ToolButton {
                            icon.name: "speedometer"
                            flat: true
                            enabled: !root.testando
                            implicitWidth: Kirigami.Units.iconSizes.small * 1.6
                            implicitHeight: implicitWidth
                            onClicked: root.testarVazao()
                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.text:
                                i18nd(root.dom, "Measure throughput (downloads ~10 MB)")
                        }
                    }

                    // Só aparece havendo um rádio MEDIDO melhor que este. Sem
                    // comparação não há conselho, e uma linha dizendo "nada a
                    // fazer" é ruído que ocupa altura em toda abertura.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.melhorBssid.length > 0
                                 && root.melhorBssid !== root.bssidAtual
                                 && root.melhorNota > root.notaAtual
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "go-jump-symbolic"
                            opacity: 0.7
                            Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        PlasmaComponents.Label {
                            text: i18nd(root.dom, "%1 measured %2", root.melhorBssid,
                                        root.melhorNota)
                            font: Kirigami.Theme.smallFont
                            opacity: 0.8
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                        }
                        PlasmaComponents.Button {
                            text: i18nd(root.dom, "Switch")
                            flat: true
                            onClicked: root.fixarPonto(root.ssid, root.melhorBssid)
                        }
                    }
                }
            }

            // ---- o rádio preferido, e até onde ele serve ------------------
            //
            // Só aparece quando há um preferido marcado nesta rede. Sem
            // preferência, esta caixa seria uma pergunta que ninguém fez.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: root.conectado && root.preferido.length > 0
                radius: Kirigami.Units.cornerRadius
                // A cor da TINTA com alfa, não `opacity` no retângulo:
                // opacidade no pai apaga o filho junto.
                color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
                implicitHeight: caixaPref.implicitHeight + Kirigami.Units.smallSpacing * 2

                ColumnLayout {
                    id: caixaPref
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing / 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "favorite"
                            Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        PlasmaComponents.Label {
                            text: i18nd(root.dom, "Preferred router")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                        }
                        PlasmaComponents.Label {
                            text: root.preferido
                                + (root.roamPrefDbm.length > 0
                                    ? "  ·  " + root.roamPrefDbm + " dBm" : "")
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                        }
                        PlasmaComponents.ToolButton {
                            icon.name: "edit-delete-remove"
                            flat: true
                            implicitWidth: Kirigami.Units.iconSizes.small * 1.4
                            implicitHeight: implicitWidth
                            onClicked: root.despreferirPonto(root.ssid)
                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.text:
                                i18nd(root.dom, "Stop preferring a router")
                        }
                    }

                    // O CORTE, que é o "sensor de qualidade" desta caixa.
                    //
                    // Enquanto o preferido estiver acima dele, é nele que se
                    // fica; abaixo, a amarra sai e o sistema escolhe sozinho.
                    // O deslizante vai de −45 (só o rádio da sala ao lado
                    // serve) a −85 (serve quase tudo o que se ouve), que é a
                    // faixa em que um enlace doméstico realmente vive.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: i18nd(root.dom, "Give it up below")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                        }
                        PlasmaComponents.Slider {
                            id: corteSlider
                            from: -85; to: -45; stepSize: 1
                            value: root.roamCorte
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            // `onMoved`, não `onValueChanged`: este último
                            // dispara também quando a leitura do sistema
                            // move o controle, e gravaria de volta o que
                            // acabou de ler, a cada oito segundos.
                            onMoved: root.ajustarLimiar("corte", Math.round(value))
                        }
                        PlasmaComponents.Label {
                            text: Math.round(corteSlider.value) + " dBm"
                            font: Kirigami.Theme.smallFont
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                            Layout.minimumWidth:   Kirigami.Units.gridUnit * 4
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.CheckBox {
                            checked: root.roamAuto
                            text: i18nd(root.dom, "Switch on its own")
                            font: Kirigami.Theme.smallFont
                            onToggled: root.ajustarLimiar("auto", checked ? 1 : 0)
                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.text: i18nd(root.dom,
                                "Switches by itself. Off, only warns.")
                        }
                        Item { Layout.fillWidth: true }
                        // O conselho vira BOTÃO quando o automático está
                        // desligado: dizer "dá para voltar" e não oferecer o
                        // caminho de volta seria informação sem saída.
                        PlasmaComponents.Button {
                            visible: !root.roamAuto && root.roamAcao === "fixar"
                            text: i18nd(root.dom, "Go back to it now")
                            icon.name: "go-jump-symbolic"
                            flat: true
                            onClicked: root.fixarPonto(root.ssid, root.preferido)
                        }
                        PlasmaComponents.Label {
                            visible: !root.roamAuto && root.roamAcao === "soltar"
                            text: i18nd(root.dom, "too weak — release it")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                        }
                    }
                }
            }

            // ---- perfis duplicados para o mesmo nome de rede ---------------
            //
            // Acontece sozinho numa casa cujo roteador anuncia WPA2 e WPA3 ao
            // mesmo tempo (modo de transição): ao entrar pelo lado WPA3, o
            // sistema trata aquilo como rede nova, pede a senha e grava um
            // SEGUNDO perfil — mesmo nome, mesmo SSID, key-mgmt `sae`. O
            // pedido de senha é a CAUSA da duplicata, não a consequência dela.
            //
            // Cuidado com a explicação fácil: eu cheguei a escrever aqui que a
            // duplicata fazia o sistema pedir a senha de novo. O journal do
            // NetworkManager desmente — "connection has security, and secrets
            // exist. No new secrets needed." —, os dois perfis têm a senha em
            // disco com psk-flags 0, e o `need-auth` que aparece no log dura
            // trinta milissegundos e não chega a ninguém.
            //
            // O que a duplicata custa de verdade: a cada conexão o sistema
            // escolhe UM dos dois ao acaso, e o perfil `sae` só entra no
            // roteador — o repetidor fala apenas PSK. Cair nele é ficar preso
            // a um aparelho só. Por isso o widget prefere o perfil WPA2 em
            // rádio de transição, e esta caixa oferece apagar o que sobra.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: root.conectado && root.perfisDaRede > 1
                spacing: Kirigami.Units.smallSpacing / 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "dialog-warning"
                        Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                    PlasmaComponents.Label {
                        text: i18ndp(root.dom,
                            "%1 saved profile for this network",
                            "%1 saved profiles for this network", root.perfisDaRede)
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }
                    PlasmaComponents.Button {
                        text: root.mostrarPerfis ? i18nd(root.dom, "Hide")
                                                 : i18nd(root.dom, "Sort it out")
                        flat: true
                        onClicked: {
                            root.mostrarPerfis = !root.mostrarPerfis;
                            if (root.mostrarPerfis) root.lerPerfis();
                        }
                    }
                }

                PlasmaComponents.Label {
                    visible: root.mostrarPerfis
                    // O texto diz o que se PODE provar. A primeira versão
                    // culpava a duplicata pelo pedido de senha; o journal do
                    // NetworkManager mostrou que os dois perfis têm a senha
                    // guardada e que ninguém é perguntado. O que sobra, e é
                    // verdade, é que dois perfis para uma rede é uma escolha
                    // ao acaso a cada conexão.
                    text: i18nd(root.dom,
                        "Two profiles for one network: the system picks by chance. Keep one.")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Repeater {
                    model: root.mostrarPerfis ? perfis : null

                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: model.nome
                            font.bold: model.ativo
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                        }
                        PlasmaComponents.Label {
                            text: root.textoSeguranca(
                                model.cripto === "sae" ? "sae"
                                : model.cripto === "wpa-psk" ? "psk" : "open")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                        }
                        PlasmaComponents.Label {
                            visible: model.ativo
                            text: i18nd(root.dom, "in use")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                        }
                        // Apagar o perfil EM USO derrubaria a conexão que a
                        // pessoa está usando para ler esta tela. O botão
                        // some ali — desabilitado, ainda convidaria ao clique.
                        PlasmaComponents.ToolButton {
                            visible: !model.ativo
                            icon.name: "edit-delete-remove"
                            flat: true
                            implicitWidth: Kirigami.Units.iconSizes.small * 1.4
                            implicitHeight: implicitWidth
                            onClicked: root.apagarPerfil(model.uuid)
                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.text:
                                i18nd(root.dom, "Remove this profile")
                        }
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
                // A SOBRA DA JANELA VAI PARA A LISTA, e não para um espaçador.
                //
                // A bandeja impõe uma altura mínima própria, quase sempre
                // maior que a soma das seções. Essa diferença ia para um Item
                // com `fillHeight` no fim da coluna e virava vão morto: dezoito
                // redes ao alcance, sete na tela e um retângulo vazio embaixo
                // do tamanho de mais quatro. Dando a sobra à lista, ela mostra
                // quantas couberem e rola o resto — que é o que uma lista faz.
                Layout.fillHeight: true
                Layout.minimumHeight: janela.alturaLinha
                model: redes
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 0

                // A lista transbordou? Um lugar só decide, porque DUAS coisas
                // dependem da resposta e elas têm de concordar: a barra
                // aparecer e a linha abrir caminho para ela. Calculadas em
                // separado, elas divergiam por um quadro e o cadeado da
                // direita piscava por baixo da barra.
                readonly property bool rolando: contentHeight > height

                // POLÍTICA EXPLÍCITA. Sem ela a barra nasce no modo do tema,
                // que a deixa transparente até o ponteiro chegar perto —
                // então numa lista que rola de verdade não havia barra
                // nenhuma na tela, e nada dizia que existia mais rede
                // embaixo. Barra que só aparece para quem já sabe que ela
                // está lá não serve para nada.
                QQC2.ScrollBar.vertical: PlasmaComponents.ScrollBar {
                    id: barra
                    policy: lista.rolando ? QQC2.ScrollBar.AlwaysOn
                                          : QQC2.ScrollBar.AlwaysOff
                }

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
                        // A barra de rolagem passa POR CIMA da última coluna:
                        // ela é sobreposta, não reserva espaço. Sem abrir
                        // caminho para ela, o cadeado da direita ficava
                        // cortado ao meio em toda lista que rolasse — e é
                        // justamente a lista cheia que rola.
                        //
                        // A folga vai DUAS vezes: uma para a barra, outra
                        // entre ela e o cadeado. Com uma só, o ícone
                        // encostava na barra — não ficava cortado, mas lia
                        // como se estivesse, e a diferença entre "encostado"
                        // e "por baixo" ninguém enxerga num ícone de 16 px.
                        //
                        // `implicitWidth`, não `width`: a largura da barra é
                        // zero enquanto ela está recolhida, e a linha se
                        // ajustaria só depois de a barra aparecer — um
                        // pulinho a cada vez que a lista cruza o limite.
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                            + (lista.rolando
                               ? barra.implicitWidth + Kirigami.Units.smallSpacing
                               : 0)
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

                        // Medido, mostra a NOTA; sem medida, a porcentagem
                        // de sinal. Não é enfeite: o sinal foi justamente o
                        // critério que errou — 700 Mb/s de taxa negociada
                        // saindo com cinco megas de internet. Onde existe
                        // medida, ela toma o lugar do palpite, e o palpite
                        // desce para a dica.
                        //
                        // Percentual não passa por catálogo: "%1%" fazia o
                        // gettext desconfiar do "%" final e rebaixar a
                        // tradução a fuzzy — e fuzzy fica em inglês.
                        PlasmaComponents.Label {
                            text: model.nota >= 0 ? model.nota
                                                  : model.sinalPct + "%"
                            opacity: model.nota >= 0 ? 0.95 : 0.6
                            font.bold: model.nota >= 0 && model.nota >= 70
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: janela.colPct
                            Layout.minimumWidth:   janela.colPct
                            Layout.maximumWidth:   janela.colPct

                            PlasmaComponents.ToolTip.visible: areaNota.containsMouse
                            PlasmaComponents.ToolTip.text:
                                root.resumoQualidade(model.bssid, true)
                                + "\n" + model.sinalPct + "%  ·  "
                                + model.dbm + " dBm"
                            MouseArea {
                                id: areaNota
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }

                        // ESTRELA e ALFINETE, e só no modo que mostra cada
                        // aparelho. Fora dele há uma linha por nome de rede, e
                        // escolher entre rádios que não estão à vista é
                        // escolher no escuro.
                        //
                        // São duas coisas diferentes, de propósito:
                        //
                        //   ★ preferir — intenção. Volta-se para este rádio
                        //     quando ele tiver sinal suficiente, e larga-se
                        //     quando não tiver. É o conserto do repetidor que
                        //     chega mais forte que o roteador em toda a casa
                        //     e, fazendo NAT sobre NAT, esconde o telefone da
                        //     sala do computador do quarto.
                        //
                        //   📌 amarrar — ordem. Fica-se NESTE rádio, sinal
                        //     bom ou ruim, até alguém soltar. Serve para
                        //     entrar no roteador principal e configurá-lo.
                        //
                        // Ambos desabilitados em rede não salva: os dois se
                        // escrevem no perfil, e perfil ainda não existe. Ficam
                        // visíveis assim mesmo, para a coluna não dançar de
                        // linha em linha.
                        PlasmaComponents.ToolButton {
                            visible: root.mostrarTodos
                            icon.name: model.preferido ? "favorite" : "rating-unrated"
                            flat: true
                            checkable: true
                            checked: model.preferido
                            enabled: model.salva
                            opacity: model.salva ? 1.0 : 0.3
                            implicitWidth: Kirigami.Units.iconSizes.small * 1.7
                            implicitHeight: implicitWidth
                            onToggled: checked
                                ? root.preferirPonto(model.nome, model.bssid)
                                : root.despreferirPonto(model.nome)
                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.text: model.salva
                                ? i18nd(root.dom, "Prefer this router while its signal holds")
                                : i18nd(root.dom, "Save the network first")
                        }

                        PlasmaComponents.ToolButton {
                            visible: root.mostrarTodos
                            icon.name: "pin-symbolic"
                            flat: true
                            checkable: true
                            checked: model.fixado
                            enabled: model.salva
                            opacity: model.salva ? 1.0 : 0.3
                            implicitWidth: Kirigami.Units.iconSizes.small * 1.7
                            implicitHeight: implicitWidth
                            onToggled: checked
                                ? root.fixarPonto(model.nome, model.bssid)
                                : root.soltarPonto(model.nome)
                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.text: model.salva
                                ? i18nd(root.dom, "Stay on this router only")
                                : i18nd(root.dom, "Save the network first")
                        }

                        // O CADEADO OCUPA LUGAR SEMPRE.
                        //
                        // Com `visible: false` num RowLayout o item sai da
                        // conta e a linha inteira encolhe: uma rede aberta no
                        // meio da lista puxava para a direita tudo o que
                        // estava à sua esquerda, e as colunas deixavam de
                        // começar no mesmo x. Rede aberta é o caso raro,
                        // então o defeito só aparecia na casa de quem tinha
                        // uma — e ali aparecia em todas as linhas de uma vez.
                        //
                        // Agora ele não some: MUDA. Sem senha, cadeado
                        // ABERTO — que é a informação que estava faltando, e
                        // não a mesma informação escondida.
                        Kirigami.Icon {
                            source: root.semSenha(model.seguranca)
                                ? "object-unlocked-symbolic"
                                : "object-locked-symbolic"
                            // Aberto tem peso próprio: é aviso de que não há
                            // senha, não decoração apagada. O desbotado
                            // continua querendo dizer "rede não salva".
                            opacity: root.semSenha(model.seguranca)
                                ? 0.9 : (model.salva ? 0.75 : 0.35)
                            Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small

                            PlasmaComponents.ToolTip.visible: areaSeg.containsMouse
                            PlasmaComponents.ToolTip.text:
                                root.textoSeguranca(model.seguranca)
                                + (model.salva ? "" : "  ·  "
                                    + i18nd(root.dom, "not saved"))
                            MouseArea {
                                id: areaSeg
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }
                    }
                }
            }

            // A legenda ensina os três símbolos da lista, em três frases
            // curtas. Ícone que precisa de explicação ou ganha legenda, ou
            // vira adivinhação — e quem usa este widget nem sempre é quem o
            // escreveu.
            // A legenda ensina os símbolos que a lista está mostrando AGORA.
            // Ensinar a estrela e o alfinete no modo simples, onde eles nem
            // aparecem, seria mandar procurar o que não está lá.
            PlasmaComponents.Label {
                text: i18nd(root.dom, "Fan number: generation.")
                    + "  " + i18nd(root.dom, "Open padlock: no password.")
                    + "  " + i18nd(root.dom, "Dimmed: not saved.")
                    + (root.mostrarTodos
                        ? "  " + i18nd(root.dom, "Star: preferred router.")
                          + "  " + i18nd(root.dom, "Pin: locked to it.")
                        : "")
                font: Kirigami.Theme.smallFont
                opacity: 0.5
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }
        }
    }
}
