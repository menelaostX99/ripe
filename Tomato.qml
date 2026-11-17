import QtQuick
import QtQuick.Shapes

// Ripe's mark: a tomato drawn on a 16-unit grid and scaled to the item. The
// body is filled from the bottom up to `level`, so on the bar it empties as
// a session runs down.
Shape {
  id: root

  property color color: "white"
  property real level: 1

  readonly property real unit: Math.min(width, height) / 16
  readonly property real empty: Math.max(0, Math.min(1, 1 - level))

  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    scale: Qt.size(root.unit, root.unit)
    strokeColor: root.color
    strokeWidth: 1.3 * root.unit
    joinStyle: ShapePath.RoundJoin
    fillColor: "transparent"
    fillGradient: fill
    PathSvg {
      path: "M8 5.6 C11.9 5.6 14.4 7.4 14.4 10.1 C14.4 13 11.7 15 8 15 C4.3 15 1.6 13 1.6 10.1 C1.6 7.4 4.1 5.6 8 5.6 Z"
    }
  }

  ShapePath {
    scale: Qt.size(root.unit, root.unit)
    strokeColor: root.color
    strokeWidth: 1.7 * root.unit
    capStyle: ShapePath.RoundCap
    fillColor: "transparent"
    PathSvg {
      path: "M8 6.4 C7.4 5 6 4.2 4.3 3.4 M8 6.4 C8 4.6 8.2 3 8.9 1.4 M8 6.4 C8.7 5 10 4.2 11.7 3.4"
    }
  }

  // A hard waterline rather than a fade: the two middle stops share a place,
  // and the whole gradient slides down the body as it empties. Moving the
  // gradient, not its stops, is what the renderer reliably repaints.
  LinearGradient {
    id: fill
    readonly property real water: (5.6 + 9.4 * root.empty) * root.unit
    x1: 0
    y1: water - 20 * root.unit
    x2: 0
    y2: water + 20 * root.unit
    GradientStop { position: 0; color: "transparent" }
    GradientStop { position: 0.4999; color: "transparent" }
    GradientStop { position: 0.5; color: root.color }
    GradientStop { position: 1; color: root.color }
  }
}
