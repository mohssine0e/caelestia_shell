import QtQuick
import QtQuick.Shapes
import Caelestia.Config
import qs.components

// ╔════════════════════════════════════════════════════════════════╗
// ║  TreeConnector — draws ONE row's tree lines:                   ║
// ║                                                                ║
// ║     │            ← spine (comes from the row above)            ║
// ║     ╰────●       ← rounded elbow + dot                         ║
// ║     │            ← spine continues down if NOT the last sibling║
// ║                                                                ║
// ║  Put it behind the row, anchors.fill the WHOLE item (row +     ║
// ║  its children) and tell it the row's height via rowHeight.     ║
// ║  All look settings are properties, set from SubtaskCard.qml.   ║
// ╚════════════════════════════════════════════════════════════════╝
Item {
    id: root

    // ── Geometry ────────────────────────────────────────────────
    property real spineX: 6            // X of the spine's CENTER line
    property real rowHeight: height    // height of this row (elbow sits at its middle)
    property bool isLast: false        // true → └ (spine stops at the elbow)
                                       // false → ├ (spine continues to the bottom)

    // ── Look ────────────────────────────────────────────────────
    property real lineWidth: 2         // use EVEN numbers for crisp lines
    property real cornerRadius: 8      // roundness of the elbow (0 = sharp corner)
    property real elbowLength: 24      // spine center → dot center (line end if no dot)
    property color lineColor: "white"

    // ── Dot ─────────────────────────────────────────────────────
    property bool showDot: true
    property bool selected: false
    property real dotSize: 6           // use EVEN numbers
    property real dotSizeSelected: 12
    property real dotOpacity: 1

    property real selectedExtension: 10


    // ── Derived (don't edit) ────────────────────────────────────
    readonly property real _cy: Math.round(rowHeight / 2)   // elbow's Y
    readonly property real _r: Math.max(0, Math.min(cornerRadius, _cy, elbowLength))
    readonly property real _dotX: spineX + elbowLength

    Behavior on lineColor { CAnim {} }

    // Curve renderer = smooth anti-aliased arcs (Qt 6.6+).
    // If the corners look jagged on your Qt, remove this line and use
    // `layer.enabled: true; layer.samples: 4` on the Shape instead.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // ── Spine (straight vertical line) ──────────────────────
        // Starts at the row's top (touching the row above / parent).
        //   last sibling → stops where the curve begins
        //   otherwise    → runs to the bottom of the whole item
        ShapePath {
            strokeColor: root.lineColor
            strokeWidth: root.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            startX: root.spineX
            startY: 0
            PathLine {
                x: root.spineX
                y: root.isLast ? root._cy - root._r : root.height
            }
        }

        // ── Branch (rounded elbow → horizontal line) ────────────
        // Leaves the spine `cornerRadius` above the row's middle,
        // bends right, then runs straight to the dot's center.
        ShapePath {
            strokeColor: root.lineColor
            strokeWidth: root.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            startX: root.spineX
            startY: root._cy - root._r
            PathArc {
                x: root.spineX + root._r
                y: root._cy
                radiusX: root._r
                radiusY: root._r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root._dotX
                y: root._cy
            }
        }
    }

    // ── Dot ─────────────────────────────────────────────────────
    // Center is fixed; only the size animates on selection.
    StyledRect {
        visible: root.showDot
        width: root.selected ? root.dotSizeSelected : root.dotSize
        height: width
        x: root._dotX - width / 2
        y: root._cy - height / 2
        radius: Tokens.rounding.full
        color: root.lineColor
        opacity: root.dotOpacity
    }
}
