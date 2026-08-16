/*
 * O símbolo do Wi-Fi com o número da geração SOBREPOSTO — em um slot de ícone.
 *
 * Desenho pedido pelo dono: o dígito ocupa do meio para baixo, por cima da
 * "anteninha", dentro do mesmo quadrado
 * (`implicitWidth === implicitHeight === tamanho`).
 *
 * Duas versões anteriores erraram o enquadramento: a primeira pôs o número
 * ao LADO e ficou com quase dois slots de largura; a segunda pôs embaixo,
 * fora dos arcos. Esta sobrepõe.
 *
 * O número é desenhado no próprio Canvas, não como Label por cima, porque
 * precisa de um contorno na cor do FUNDO para não se misturar aos arcos —
 * texto e traço têm a mesma cor de tema, e sem o contorno o resultado é
 * borrão. Isso só dá para fazer no contexto de desenho.
 *
 * Nenhum dos 286 ícones de Wi-Fi dos temas instalados tem variante com
 * número (conferido em 2026-08-15), por isso é desenhado à mão. Cores saem
 * de Kirigami.Theme, então acompanham tema claro/escuro sozinhas.
 *
 * Arcos apagados ficam translúcidos em vez de sumir: enlace fraco continua
 * PARECENDO conectado, que é o que ele é.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: raiz

    // 0 = desconectado; 1..3 = arcos acesos
    property int barras: 0
    // "6", "6E", "5", "4" — vazio desenha só os arcos
    property string numero: ""
    // "wifi" desenha o leque; "mix", o leque com um ponto no canto oposto ao
    // número, dizendo que há um segundo enlace ativo.
    //
    // O caso "cabo" NÃO é desenhado aqui: quem mostra é o `network-wired-symbolic`
    // do próprio tema, que o Plasma já usa para rede cabeada e tinge junto com
    // a fileira. Cheguei a desenhar uma tomada RJ45 à mão neste Canvas e a
    // joguei fora — mesma lição do widget de clima: conjunto pronto e
    // profissional ganha do traço caseiro, e ainda acompanha troca de tema.
    //
    // O ponto vai à ESQUERDA de propósito: o canto inferior direito já é do
    // número da geração, e empilhar as duas marcas ali é o borrão que este
    // projeto rejeita desde o contador do WhatsApp.
    property string modo: "wifi"
    property real tamanho: Kirigami.Units.iconSizes.smallMedium

    // Quadrado, sempre: é o que faz caber em um slot da bandeja.
    implicitWidth: tamanho
    implicitHeight: tamanho

    // Herda o contexto de cor de quem contém — no painel isso é o conjunto
    // Complementary, que é o motivo de os ícones da bandeja saírem claros
    // sobre painel escuro mesmo em tema claro. Sem herdar, o desenho usaria
    // as cores da JANELA e destoaria dos vizinhos.
    Kirigami.Theme.inherit: true

    Canvas {
        id: leque
        anchors.fill: parent

        readonly property color cor: Kirigami.Theme.textColor
        readonly property string familia: Kirigami.Theme.defaultFont.family

        onCorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: raiz
            function onBarrasChanged() { leque.requestPaint(); }
            function onNumeroChanged() { leque.requestPaint(); }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const w = width, h = height;
            const lw = Math.max(1, w * 0.115);
            const raioPonto = lw * 0.62;

            // Margem para o TRAÇO não ser cortado. As pontas dos arcos ficam
            // a 225° e 315°, ou seja em x = cx ± r·cos45 — sem reservar meia
            // espessura, a ponta do arco de fora sai da tela.
            const m = lw / 2 + w * 0.03;
            const COS45 = Math.SQRT1_2;

            // O raio maior é o menor entre o que cabe na largura e o que
            // cabe na altura. Calculado, não arbitrado.
            let r = Math.min((w / 2 - m) / COS45, h - 2 * m - raioPonto);
            r = Math.max(r, lw);

            // Centragem pela TINTA, não pela linha teórica. O arco é traço
            // com espessura: ele sobe meia espessura acima do raio. Ignorar
            // isso deixava o desenho 'lw/2' baixo demais — folga de 2,42 em
            // cima contra 3,69 embaixo num ícone de 22px.
            const alturaTinta = r + lw / 2 + raioPonto;
            const cx = w / 2;
            const cy = (h - alturaTinta) / 2 + r + lw / 2;

            ctx.lineWidth = lw;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.strokeStyle = cor;
            ctx.fillStyle = cor;


            // Ponto na base. Existe sempre — o que varia é o alcance.
            ctx.globalAlpha = raiz.barras > 0 ? 1.0 : 0.35;
            ctx.beginPath();
            ctx.arc(cx, cy, raioPonto, 0, Math.PI * 2);
            ctx.fill();

            // Três arcos abrindo para cima, de 225° a 315°. O primeiro nasce
            // logo acima do ponto; o terceiro é exatamente o raio máximo.
            const r1 = raioPonto + lw * 1.15;
            const passo = (r - r1) / 2;
            for (let i = 0; i < 3; i++) {
                ctx.globalAlpha = (i < raiz.barras) ? 1.0 : 0.28;
                ctx.beginPath();
                ctx.arc(cx, cy, r1 + passo * i,
                        Math.PI * 1.25, Math.PI * 1.75);
                ctx.stroke();
            }
            ctx.globalAlpha = 1.0;

            // ---- o número, por cima, do meio para baixo -------------------
            if (raiz.numero.length === 0) {
                if (raiz.modo === "mix") {
                    const rp0 = Math.max(1.2, w * 0.085);
                    ctx.globalCompositeOperation = "destination-out";
                    ctx.beginPath();
                    ctx.arc(m + rp0, h - m - rp0, rp0 * 2.0, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.globalCompositeOperation = "source-over";
                    ctx.fillStyle = cor;
                    ctx.beginPath();
                    ctx.arc(m + rp0, h - m - rp0, rp0, 0, Math.PI * 2);
                    ctx.fill();
                }
                return;
            }

            // "6E" tem dois caracteres e precisa caber na mesma largura.
            const fator = raiz.numero.length > 1 ? 0.38 : 0.50;
            const px = Math.max(7, Math.round(h * fator));

            // Peso normal, não negrito: sobreposto aos arcos, o negrito
            // empasta. Pedido do dono.
            ctx.font = px + "px \"" + familia + "\"";

            // Ancorado no canto inferior direito, não centrado num ponto
            // arbitrário. A versão anterior usava linha de base no MEIO em
            // y = 0,76·h com corpo de 0,56·h: o glifo ia até 1,04·h e era
            // cortado pela borda. Com âncora de canto, não há como estourar.
            ctx.textAlign = "right";
            ctx.textBaseline = "alphabetic";

            // A base do dígito acompanha a base do LEQUE, não a da tela.
            // Preso na borda inferior ele descia abaixo da tinta e ficava
            // solto; preso ao símbolo, sobrepõe os arcos de baixo — que é o
            // desenho pedido. O `min` garante que não estoure mesmo assim.
            const nx = w - m;
            const ny = Math.min(h - m, cy + raioPonto + lw * 0.2);

            // Abre o vão APAGANDO o arco atrás do dígito, em vez de pintar
            // por cima com a cor de fundo. Pintar exigiria adivinhar o fundo
            // — e num painel translúcido a "cor de fundo" do tema vira um
            // borrão sólido. "destination-out" deixa o vão transparente de
            // verdade, seja qual for o painel.
            ctx.globalAlpha = 1.0;
            ctx.globalCompositeOperation = "destination-out";
            ctx.lineWidth = Math.max(1.5, h * 0.10);
            ctx.lineJoin = "round";
            ctx.strokeStyle = "#000";
            ctx.strokeText(raiz.numero, nx, ny);

            ctx.globalCompositeOperation = "source-over";
            ctx.globalAlpha = raiz.barras > 0 ? 1.0 : 0.45;
            ctx.fillStyle = cor;
            ctx.fillText(raiz.numero, nx, ny);
            ctx.globalAlpha = 1.0;

            // Segundo enlace ativo: um ponto no canto inferior ESQUERDO, com
            // o mesmo vão aberto por trás. Dois gateways distintos ao mesmo
            // tempo é balanceamento ou redundância, e o ícone precisa dizer
            // isso sem virar dois desenhos espremidos num quadrado de 22 px.
            if (raiz.modo === "mix") {
                const rp = Math.max(1.2, w * 0.085);
                const px2 = m + rp, py2 = h - m - rp;
                ctx.globalCompositeOperation = "destination-out";
                ctx.beginPath();
                ctx.arc(px2, py2, rp * 2.0, 0, Math.PI * 2);
                ctx.fill();
                ctx.globalCompositeOperation = "source-over";
                ctx.fillStyle = cor;
                ctx.beginPath();
                ctx.arc(px2, py2, rp, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }
}
