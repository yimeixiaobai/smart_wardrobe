import SwiftUI

/// 加载等待期间轮播穿搭小贴士
struct LoadingTipsView: View {
    @State private var currentIndex = 0
    @State private var timer: Timer?

    private static let tips = [
        "同色系搭配是最不容易出错的选择",
        "一身搭配颜色不超过三种更显高级",
        "基础款百搭单品是衣橱的核心",
        "适当的配饰能提升整体质感",
        "穿搭的关键是比例，上短下长显腿长",
        "天冷时内搭浅色会比全黑更有层次",
        "牛仔裤几乎能搭配衣橱里的一切",
        "好的穿搭不在于贵，在于和谐",
    ]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(Self.tips[currentIndex])
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .id(currentIndex)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentIndex = (currentIndex + 1) % Self.tips.count
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Shimmer Modifier

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 300)
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
