//
//  ContourOverlay.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//
//  Render de contornos detectados por Vision (Suzuki) como overlay SwiftUI.
//

import SwiftUI
import Vision

struct ContourOverlay: View {
    let contours: [VNContour]
    let imageSize: CGSize // tamaño del CGImage mostrado
    let strokeColor: Color

    var body: some View {
        Canvas { context, canvasSize in
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            // Escalas de mapeo de coordenadas de imagen → canvas
            let scaleX = canvasSize.width / imageSize.width
            let scaleY = canvasSize.height / imageSize.height

            for contour in contours {
                // Construye un path en coordenadas de imagen (pixeles), luego escala a canvas
                guard let cgPath = contour.pathInImage(ofSize: imageSize) else { continue }

                var scale = CGAffineTransform(scaleX: scaleX, y: scaleY)
                let scaledPath = cgPath.copy(using: &scale) ?? cgPath

                context.stroke(Path(scaledPath), with: .color(strokeColor), lineWidth: 1.5)
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

private extension VNContour {
    // Devuelve un CGPath en coordenadas de imagen (0...imageSize)
    func pathInImage(ofSize imageSize: CGSize) -> CGPath? {
        let count = pointCount
        guard count > 0 else { return nil }

        // VNContour solo expone puntos normalizados (0...1)
        let normalized = self.normalizedPoints
        guard normalized.count == count else { return nil }

        let path = CGMutablePath()
        var first = true
        for p in normalized {
            // Convertir a coordenadas de imagen (pixeles)
            let imgPoint = CGPoint(x: CGFloat(p.x) * imageSize.width,
                                   y: CGFloat(p.y) * imageSize.height)
            if first {
                path.move(to: imgPoint)
                first = false
            } else {
                path.addLine(to: imgPoint)
            }
        }
        path.closeSubpath()
        return path
    }
}

