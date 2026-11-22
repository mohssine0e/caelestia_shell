pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Rectangle {
    id: root

    required property var diagram
    property bool expanded: false
    readonly property color lineColor: Qt.alpha(Colours.palette.m3primary, 0.7)
    readonly property real nodeHeight: 48
    readonly property real nodeWidth: Math.max(82, Math.min(168,
        (width - 32) / Math.max(1, (diagram.layers || []).length) - 16))
    readonly property real graphHeight: 24 + maxLayerSize() * 76
    readonly property var nodeLayout: {
        const currentDiagram = diagram
        const currentWidth = width
        const currentNodeWidth = nodeWidth
        return buildLayout(currentDiagram, currentWidth, currentNodeWidth)
    }

    function maxLayerSize(): int {
        let count = 1
        for (const layer of diagram.layers || []) count = Math.max(count, layer.length)
        return count
    }

    function buildLayout(data, availableWidth, computedNodeWidth): var {
        const labels = ({})
        for (const node of data.nodes || []) labels[node.id] = String(node.label || node.id)
        const result = []
        const columnWidth = (availableWidth - 24) / Math.max(1, (data.layers || []).length)
        for (let row = 0; row < (data.layers || []).length; row++) {
            const layer = data.layers[row]
            if (!layer || !layer.length) continue
            const left = 12 + row * columnWidth + (columnWidth - computedNodeWidth) / 2
            const top = 12 + (maxLayerSize() - layer.length) * 38
            for (let col = 0; col < layer.length; col++) {
                const id = String(layer[col])
                if (labels[id]) result.push({ id: id, label: labels[id],
                    x: left, y: top + col * 76 })
            }
        }
        return result
    }

    function findNode(id): var {
        for (const node of nodeLayout) if (node.id === id) return node
        return null
    }

    width: parent?.width ?? 0
    implicitHeight: 42 + (expanded ? graphHeight + (caption.visible ? caption.implicitHeight + 14 : 0) : 0)
    radius: Tokens.rounding.small
    color: Colours.palette.m3surfaceContainerLow
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.65)

    RowLayout {
        id: header
        x: 11
        y: 7
        width: root.width - 22
        height: 28
        spacing: 8

        MaterialIcon {
            text: "account_tree"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.size(16).build()
        }
        StyledText {
            Layout.fillWidth: true
            text: root.diagram.title || qsTr("Diagram")
            color: Colours.palette.m3onSurface
            font: Qt.font({ family: Tokens.font.label.medium.family, pixelSize: 13,
                weight: Font.DemiBold })
            elide: Text.ElideRight
        }
        MaterialIcon {
            text: root.expanded ? "expand_less" : "expand_more"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.size(16).build()
        }
    }
    MouseArea {
        anchors.left: header.left
        anchors.right: header.right
        anchors.top: header.top
        anchors.bottom: header.bottom
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded
    }

    Item {
        id: graph
        x: 8
        y: 40
        width: root.width - 16
        height: root.graphHeight
        visible: root.expanded
        clip: true

        Canvas {
            id: connectors
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = root.lineColor.toString()
                ctx.fillStyle = root.lineColor.toString()
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                for (const edge of root.diagram.edges || []) {
                    const source = root.findNode(edge.from)
                    const target = root.findNode(edge.to)
                    if (!source || !target) continue
                    const x1 = source.x + root.nodeWidth
                    const y1 = source.y + root.nodeHeight / 2
                    const x2 = target.x
                    const y2 = target.y + root.nodeHeight / 2
                    const angle = Math.atan2(y2 - y1, x2 - x1)
                    ctx.beginPath()
                    ctx.moveTo(x1, y1)
                    ctx.lineTo(x2 - 4, y2)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(x2, y2)
                    ctx.lineTo(x2 - 7 * Math.cos(angle - 0.5), y2 - 7 * Math.sin(angle - 0.5))
                    ctx.lineTo(x2 - 7 * Math.cos(angle + 0.5), y2 - 7 * Math.sin(angle + 0.5))
                    ctx.closePath()
                    ctx.fill()
                }
            }
            onWidthChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()
            Connections {
                target: root
                function onNodeLayoutChanged(): void { connectors.requestPaint() }
                function onLineColorChanged(): void { connectors.requestPaint() }
            }
        }

        Repeater {
            model: root.nodeLayout
            delegate: Rectangle {
                id: nodePill
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: root.nodeWidth
                height: root.nodeHeight
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3primary, 0.55)
                StyledText {
                    anchors.fill: parent
                    anchors.margins: 5
                    text: nodePill.modelData.label
                    color: Colours.palette.m3onSurface
                    font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 12,
                        weight: Font.Medium })
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    StyledText {
        id: caption
        x: 11
        y: graph.y + graph.height + 1
        width: root.width - 22
        visible: root.expanded && !!root.diagram.caption
        text: root.diagram.caption || ""
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.WordWrap
    }
}
