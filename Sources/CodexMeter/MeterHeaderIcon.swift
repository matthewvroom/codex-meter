import SwiftUI

struct MeterHeaderIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: 0.114, green: 0.133, blue: 0.169))
                .padding(3)

            Path { path in
                path.addArc(
                    center: CGPoint(x: 18, y: 18),
                    radius: 10.5,
                    startAngle: .degrees(135),
                    endAngle: .degrees(405),
                    clockwise: false
                )
            }
            .stroke(
                Color(red: 0.125, green: 0.773, blue: 0.933),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )

            Path { path in
                path.move(to: CGPoint(x: 18, y: 18))
                path.addLine(to: CGPoint(x: 22.5, y: 12.5))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))

            Circle()
                .fill(.white)
                .frame(width: 3.5, height: 3.5)

            Path { path in
                path.move(to: CGPoint(x: 14, y: 24))
                path.addLine(to: CGPoint(x: 17, y: 26))
                path.addLine(to: CGPoint(x: 14, y: 28))
                path.move(to: CGPoint(x: 20, y: 28))
                path.addLine(to: CGPoint(x: 23, y: 28))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 36, height: 36)
    }
}
