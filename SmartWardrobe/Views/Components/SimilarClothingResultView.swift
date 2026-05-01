import SwiftUI

/// 相似衣物检测结果视图
/// 在上传前发现相似衣物时，以 sheet 形式弹出供用户决策
struct SimilarClothingResultView: View {
    let result: SimilarityCheckService.CheckResult
    let newImage: UIImage?
    let onSaveAnyway: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection()
                    newImageSection()
                    similarItemsSection()
                    actionButtons()
                }
                .padding()
            }
            .navigationTitle("发现相似衣物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { onCancel() }
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection() -> some View {
        VStack(spacing: 10) {
            Image(systemName: result.hasDuplicate
                  ? "exclamationmark.triangle.fill"
                  : "eye.trianglebadge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(result.hasDuplicate ? .red : .orange)

            Text(result.hasDuplicate
                 ? "衣橱中已有疑似相同的衣物"
                 : "衣橱中有高度相似的衣物")
                .font(.headline)

            Text("请确认是否仍要保存，避免重复添加或购买相似款式")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - New Image Preview

    @ViewBuilder
    private func newImageSection() -> some View {
        if let newImage {
            VStack(spacing: 6) {
                Text("待添加")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(uiImage: newImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .background(checkerboard())
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
            }
        }
    }

    // MARK: - Similar Items List

    @ViewBuilder
    private func similarItemsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("相似衣物")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ForEach(result.matches) { match in
                similarItemRow(match)
            }
        }
    }

    @ViewBuilder
    private func similarItemRow(_ match: SimilarityCheckService.SimilarMatch) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumb = match.thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .background(checkerboard())
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "tshirt")
                            .foregroundStyle(.secondary)
                    }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(match.clothingItem.displayName)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: match.level.icon)
                        .font(.caption2)
                    Text(match.level.label)
                        .font(.caption)
                }
                .foregroundStyle(match.level == .duplicate ? .red : .orange)

                if let categoryName = match.clothingItem.category?.name {
                    Text(categoryName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Similarity percentage (rough visual indicator)
            similarityBadge(score: match.score)
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func similarityBadge(score: Float) -> some View {
        let percent = max(0, min(100, Int(score * 100)))
        VStack(spacing: 2) {
            Text("\(percent)%")
                .font(.headline.monospacedDigit())
                .foregroundStyle(score > 0.85 ? .red : .orange)
            Text("相似")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionButtons() -> some View {
        VStack(spacing: 12) {
            Button {
                onCancel()
            } label: {
                Text("取消保存")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                onSaveAnyway()
            } label: {
                Text("仍然保存")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func checkerboard() -> some View {
        Canvas { context, size in
            let t: CGFloat = 8
            for row in 0..<Int(size.height / t) + 1 {
                for col in 0..<Int(size.width / t) + 1 {
                    let rect = CGRect(x: CGFloat(col) * t, y: CGFloat(row) * t, width: t, height: t)
                    context.fill(Path(rect), with: .color((row + col) % 2 == 0 ? .white : Color(.systemGray5)))
                }
            }
        }
    }
}
