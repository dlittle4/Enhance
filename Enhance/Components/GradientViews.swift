import SwiftUI

// MARK: - Button Background Gradient
// This gradient creates a smooth, diffused effect using MeshGradient
struct SimpleGradientBackground: View {
    var width: Int = 3
    var height: Int = 3
    var primaryColors: [Color] = [
        Color(red: 0.231, green: 1.0, blue: 0.988),   Color(red: 0.122, green: 0.773, blue: 0.580),  Color(red: 0.765, green: 0.467, blue: 0.863),
        Color(red: 0.157, green: 0.851, blue: 0.714),  Color(red: 0.086, green: 0.698, blue: 0.443),  Color(red: 0.988, green: 0.388, blue: 1.0),
        Color(red: 0.231, green: 1.0, blue: 0.988),   Color(red: 0.196, green: 0.659, blue: 0.514),  Color(red: 0.537, green: 0.545, blue: 0.722)
    ]
    var secondaryColors: [Color] = [
        Color(red: 0.157, green: 0.851, blue: 0.714),  Color(red: 0.086, green: 0.698, blue: 0.443),  Color(red: 0.988, green: 0.388, blue: 1.0),
        Color(red: 0.231, green: 1.0, blue: 0.988),   Color(red: 0.196, green: 0.659, blue: 0.514),  Color(red: 0.765, green: 0.467, blue: 0.863),
        Color(red: 0.157, green: 0.851, blue: 0.714),  Color(red: 0.122, green: 0.773, blue: 0.580),  Color(red: 0.988, green: 0.388, blue: 1.0)
    ]
    var positionAnimationDuration: Double = 3.0
    var colorAnimationDuration: Double = 5.0
    /// Set to a value > 0 to apply GPU pixelation. Larger values = chunkier pixels.
    var pixelSize: CGFloat = 8

    @State private var isAnimating = false
    @State private var isColorToggled = false
    
    var body: some View {
        GeometryReader { geo in
            MeshGradient(width: width, height: height,
                         locations: .points([
                            SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
                            SIMD2<Float>(0.0, 0.5), SIMD2<Float>(isAnimating ? 0.1 : 0.8, 0.5), SIMD2<Float>(1.0, isAnimating ? 0.5 : 1.0),
                            SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0)
                         ]),
                         colors: .colors(isColorToggled ? secondaryColors : primaryColors),
                         smoothsColors: true)
            .layerEffect(
                ShaderLibrary.pixellate(.float(pixelSize), .float2(geo.size)),
                maxSampleOffset: CGSize(width: pixelSize, height: pixelSize)
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: positionAnimationDuration).repeatForever(autoreverses: true)) {
                isAnimating.toggle()
            }
            withAnimation(.easeInOut(duration: colorAnimationDuration).repeatForever(autoreverses: true)) {
                isColorToggled.toggle()
            }
        }
    }
}

// MARK: - Border Gradient Animation
// Creates a soft, diffused border effect that matches Apple's gradient style
struct SimpleGradientBorder: View {
    // Configuration parameters
    var primaryGradient = Gradient(colors: [
        Color(red: 0.0, green: 0.5, blue: 0.9),    // Start color
        Color(red: 0.8, green: 0.2, blue: 0.9)     // End color
    ])
    
    var secondaryGradient = Gradient(colors: [
        Color(red: 0.95, green: 0.3, blue: 0.7),   // Start color
        Color(red: 0.95, green: 0.1, blue: 0.4)    // End color
    ])
    
    // Animation durations
    var rotationDuration: Double = 10.0
    var colorChangeDuration: Double = 3.0
    
    // Animation state
    @State private var isColorToggled = false
    
    var body: some View {
        TimelineView(.animation) { timeline in
            // Compute rotation angle based on current time
            let now = timeline.date.timeIntervalSinceReferenceDate
            let angle = now.remainder(dividingBy: rotationDuration) * 36 // Convert to degrees (36° per second)
            
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(lineWidth: 6)
                .foregroundColor(.clear)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(lineWidth: 6)
                        .foregroundColor(.clear)
                        .background(
                            AngularGradient(
                                gradient: isColorToggled ? secondaryGradient : primaryGradient,
                                center: .center,
                                angle: .degrees(angle)
                            )
                            .opacity(0.85)
                            .scaleEffect(1)
                            .mask(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(lineWidth: 6)
                                    .scaleEffect(1)
                            )
                        )
                )
                .onAppear {
                    // Animate color changes
                    withAnimation(.easeInOut(duration: colorChangeDuration).repeatForever(autoreverses: true)) {
                        isColorToggled.toggle()
                    }
                }
        }
    }
}

// Preview for the components
struct GradientViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 30) {
            Group {
                Text("Gradient Backgrounds")
                    .font(.headline)
                    .foregroundColor(.white)
                
                VStack(spacing: 20) {
                    Text("Standard Mesh")
                        .foregroundColor(.white)
                    SimpleGradientBackground()
                        .frame(height: 60)
                        .cornerRadius(8)
                    
                    Text("Custom Colors")
                        .foregroundColor(.white)
                    SimpleGradientBackground(
                        primaryColors: [.blue, .green, .blue,
                                      .green, .teal, .green,
                                      .blue, .green, .blue],
                        secondaryColors: [.purple, .indigo, .blue,
                                        .indigo, .purple, .indigo,
                                        .blue, .indigo, .purple]
                    )
                        .frame(height: 60)
                        .cornerRadius(8)
                    
                    Text("Faster Animation")
                        .foregroundColor(.white)
                    SimpleGradientBackground(
                        positionAnimationDuration: 1.5,
                        colorAnimationDuration: 2.0
                    )
                        .frame(height: 60)
                        .cornerRadius(8)
                }
                .previewDisplayName("Gradient Backgrounds")
            }
            
            Divider()
                .background(Color.white)
                .padding(.vertical)
            
            Group {
                Text("Gradient Borders")
                    .font(.headline)
                    .foregroundColor(.white)
                
                VStack(spacing: 20) {
                    Text("Standard Border")
                        .foregroundColor(.white)
                    SimpleGradientBorder()
                        .frame(width: 200, height: 60)
                    
                    Text("As Button Border")
                        .foregroundColor(.white)
                    ZStack {
                        SimpleGradientBorder()
                        Text("BUTTON")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                    .frame(width: 200, height: 60)
                }
                .previewDisplayName("Gradient Borders")
            }
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
} 
