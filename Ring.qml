import QtQuick
import QtQuick.Shapes

// A ring that empties clockwise from the top, like a clock hand sweeping, as
// `remaining` falls from 1 to 0, over a faint full track. Used large in the panel and small on the bar.
Shape {
  id: root

  property real remaining: 1
  property color color: "white"
  property color trackColor: "gray"
  property real lineWidth: 6
  // A filled centre, for the bar icon.
  property real dotRadius: 0

  readonly property real fraction: Math.max(0, Math.min(1, remaining))
  readonly property real ringRadius: Math.max(0, (Math.min(width, height) - lineWidth) / 2)

  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    strokeColor: root.trackColor
    strokeWidth: root.lineWidth
    fillColor: "transparent"
    PathAngleArc {
      centerX: root.width / 2
      centerY: root.height / 2
      radiusX: root.ringRadius
      radiusY: root.ringRadius
      startAngle: 0
      sweepAngle: 360
    }
  }

  ShapePath {
    strokeColor: root.remaining > 0.001 ? root.color : "transparent"
    strokeWidth: root.lineWidth
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    PathAngleArc {
      centerX: root.width / 2
      centerY: root.height / 2
      radiusX: root.ringRadius
      radiusY: root.ringRadius
      startAngle: -90 + 360 * (1 - root.fraction)
      sweepAngle: 360 * root.fraction
    }
  }

  ShapePath {
    strokeColor: "transparent"
    strokeWidth: 0
    fillColor: root.dotRadius > 0 ? root.color : "transparent"
    PathAngleArc {
      centerX: root.width / 2
      centerY: root.height / 2
      radiusX: root.dotRadius
      radiusY: root.dotRadius
      startAngle: 0
      sweepAngle: 360
    }
  }
}
