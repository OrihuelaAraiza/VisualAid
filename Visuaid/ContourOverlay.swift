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
        Canvas { context, size in
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let scaleX = size.width / imageSize.width
            let scaleY = size.height / imageSize.height

            for contour in contours {
                if let path = contour.normalizedPath {
                    var cgPath = path.copy()
                    var transform = CGAffineTransform(scaleX: imageSize.width, y: imageSize.height)
                    cgPath = cgPath.copy(using: &transform) ?? cgPath
                    var scale = CGAffineTransform(scaleX: scaleX, y: scaleY)
                    cgPath = cgPath.copy(using: &scale) ?? cgPath

                    context.stroke(Path(cgPath), with: .color(strokeColor), lineWidth: 1.5)
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

private extension VNContour {
    var normalizedPath: CGPath? {
        var points: [CGPoint] = []
        do {
            try self.enumeratePoints { point, _ in
                points.append(CGPoint(x: CGFloat(point.x), y: CGFloat(1 - point.y))) // invertir Y
            }
        } catch {
            return nil
        }
        let path = CGMutablePath()
        if let first = points.first {
            path.move(to: first)
            for p in points.dropFirst() {
                path.addLine(to: p)
            }
            path.closeSubpath()
        }
        return path
    }
}
