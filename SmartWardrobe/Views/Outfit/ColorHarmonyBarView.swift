import SwiftUI

struct ColorHarmonyBarView: View {
    let hexColorSets: [[String]]
    @Binding var isExpanded: Bool

    var body: some View {
        let result = ColorHarmonyService.analyze(hexColors: hexColorSets)

        if isExpanded {
            expandedView(result)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            compactView(result)
        }
    }

    @ViewBuilder
    private func expandedView(_ result: ColorHarmonyService.HarmonyResult) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: result.level.icon)
                    .foregroundStyle(result.level.color)
                Text("配色评分")
                    .font(.caption.bold())
                Spacer()
                Text("\(result.score)")
                    .font(.title2.bold())
                    .foregroundStyle(result.level.color)
                Text("/100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(Array(hexColorSets.enumerated()), id: \.offset) { _, hexSet in
                    if let firstHex = hexSet.first {
                        Circle()
                            .fill(Color(hex: firstHex))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    }
                }
                Spacer()
                Text(result.level.label)
                    .font(.caption.bold())
                    .foregroundStyle(result.level.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(result.level.color.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text(result.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !result.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(result.suggestions, id: \.self) { suggestion in
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text(suggestion)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    @ViewBuilder
    private func compactView(_ result: ColorHarmonyService.HarmonyResult) -> some View {
        HStack(spacing: 6) {
            Image(systemName: result.level.icon)
                .font(.caption2)
                .foregroundStyle(result.level.color)
            Text("配色: \(result.level.label) \(result.score)分")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("点击查看详情")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded = true
            }
        }
    }
}
