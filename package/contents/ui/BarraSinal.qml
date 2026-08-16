/*
 * Barra de sinal: quatro degraus, lidos de relance.
 *
 * A cor entra SÓ NOS EXTREMOS. Um degradê contínuo do verde ao vermelho
 * pinta de amarelo a maior parte das redes — o olho passa a comparar
 * matizes parecidos em vez de contar degraus, e a fileira inteira fica
 * berrante ao lado de um painel monocromático. Aqui o normal é a cor do
 * tema; verde e vermelho aparecem só quando há algo a dizer: um sinal
 * folgado (acima de −55 dBm) ou um que vai doer (abaixo de −80).
 *
 * O corte é em dBm, não em porcento: o porcento já é uma conversão linear
 * grosseira, e reconverter para escolher cor erraria duas vezes.
 *
 * Nenhuma cor escrita à mão — positive/negative/textColor são do tema, e
 * acompanham claro e escuro.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: barra

    property int nivel: 0     // degraus acesos, 0 a 4
    property int dbm: 0       // potência medida; 0 quando não se sabe

    implicitWidth:  Kirigami.Units.iconSizes.small
    implicitHeight: Kirigami.Units.iconSizes.small

    readonly property color corAcesa:
        dbm === 0   ? Kirigami.Theme.textColor
      : dbm <= -80  ? Kirigami.Theme.negativeTextColor
      : dbm >= -55  ? Kirigami.Theme.positiveTextColor
      :               Kirigami.Theme.textColor

    Repeater {
        model: 4
        // Sem Row: um posicionador administra o x dos filhos e briga com o
        // y que cada degrau precisa para nascer na base. Com x e y próprios
        // a escada é explícita e não depende de quem alinha o quê.
        delegate: Rectangle {
            readonly property real passo: barra.width / 4
            width:  Math.max(2, Math.round(passo * 0.58))
            height: Math.max(2, Math.round(barra.height * (0.34 + 0.22 * index)))
            x: Math.round(index * passo)
            y: barra.height - height
            radius: width / 3
            color: barra.corAcesa
            // Os degraus apagados continuam visíveis, fracos: some-los faria
            // a barra mudar de comprimento a cada rede, e o olho perderia a
            // régua que torna a comparação possível.
            opacity: index < barra.nivel ? 1.0 : 0.2
        }
    }
}
