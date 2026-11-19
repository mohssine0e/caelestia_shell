import QtQuick
import QtQuick.Shapes
import Caelestia
import Caelestia.Config
import qs.services

Item {
    id: root

    // "right": docked against right screen edge (exposed: top, left, bottom)
    // "left":  docked against left bar/screen edge (exposed: top, right, bottom)
    // "top":   docked against top screen edge (exposed: left, bottom, right)
    // "bottom": docked against bottom screen edge (exposed: left, top, right)
    // "all":   detached/floating (all 4 edges exposed)
    property string edge: "right"
    property real radius: Tokens.rounding.extraLarge
    property real borderWidth: Math.max(1, Config.border.thickness)
    property color borderColor: Colours.palette.m3primary
    property real edgeOverlap: 2

    // Pass through pointer events so borders never block interactions
    enabled: false

    readonly property real half: borderWidth / 2
    readonly property real w: width
    readonly property real h: height
    readonly property real clampedRadius: Math.max(0, Math.min(radius, Math.min((w - borderWidth) / 2, (h - borderWidth) / 2)))

    Shape {
        id: shape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        layer.enabled: true
        layer.smooth: true

        // Left-docked popout: open on left, exposed on top, right, bottom
        ShapePath {
            strokeWidth: root.edge === "left" ? root.borderWidth : 0
            strokeColor: root.edge === "left" ? root.borderColor : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.MiterJoin

            startX: -root.edgeOverlap
            startY: root.h - root.half

            PathLine {
                x: Math.max(0, root.w - root.clampedRadius - root.half)
                y: root.h - root.half
            }
            PathArc {
                x: root.w - root.half
                y: Math.max(0, root.h - root.clampedRadius - root.half)
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.w - root.half
                y: root.clampedRadius + root.half
            }
            PathArc {
                x: Math.max(0, root.w - root.clampedRadius - root.half)
                y: root.half
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: -root.edgeOverlap
                y: root.half
            }
        }

        // Right-docked popout: open on right, exposed on top, left, bottom
        ShapePath {
            strokeWidth: root.edge === "right" ? root.borderWidth : 0
            strokeColor: root.edge === "right" ? root.borderColor : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.MiterJoin

            startX: root.w + root.edgeOverlap
            startY: root.half

            PathLine {
                x: root.clampedRadius + root.half
                y: root.half
            }
            PathArc {
                x: root.half
                y: root.clampedRadius + root.half
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.half
                y: Math.max(0, root.h - root.clampedRadius - root.half)
            }
            PathArc {
                x: root.clampedRadius + root.half
                y: root.h - root.half
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.w + root.edgeOverlap
                y: root.h - root.half
            }
        }

        // Fully detached / floating popout: all 4 edges exposed
        ShapePath {
            strokeWidth: root.edge === "all" ? root.borderWidth : 0
            strokeColor: root.edge === "all" ? root.borderColor : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.MiterJoin

            startX: root.clampedRadius + root.half
            startY: root.half

            PathLine {
                x: Math.max(0, root.w - root.clampedRadius - root.half)
                y: root.half
            }
            PathArc {
                x: root.w - root.half
                y: root.clampedRadius + root.half
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.w - root.half
                y: Math.max(0, root.h - root.clampedRadius - root.half)
            }
            PathArc {
                x: Math.max(0, root.w - root.clampedRadius - root.half)
                y: root.h - root.half
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.clampedRadius + root.half
                y: root.h - root.half
            }
            PathArc {
                x: root.half
                y: Math.max(0, root.h - root.clampedRadius - root.half)
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.half
                y: root.clampedRadius + root.half
            }
            PathArc {
                x: root.clampedRadius + root.half
                y: root.half
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
                direction: PathArc.Clockwise
            }
        }
    }
}
