import SwiftUI
import os.log

private let logger = Logger(subsystem: "SmartWardrobe", category: "ClothingDetail")

struct ClothingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: ClothingItem

    @State private var selectedTab = 0
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingOutfitCanvas = false
    @State private var showingWearHistory = false
    @State private var showingImageEditor = false

    private let imageService = ImageStorageService.shared
    private let tabs = ["详情", "搭配", "推荐"]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerImage()
                wearCountBar()
                tabSelector()
                Divider()

                switch selectedTab {
                case 0: detailContent()
                case 1: outfitContent()
                case 2: recommendContent()
                default: EmptyView()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑属性", systemImage: "pencil") {
                        showingEditSheet = true
                    }
                    if item.imageFileName != nil {
                        Button("编辑图片", systemImage: "photo") {
                            showingImageEditor = true
                        }
                    }
                    Button("永久删除", systemImage: "trash", role: .destructive) {
                        showingDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar()
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                ClothingEditView(item: item)
            }
        }
        .fullScreenCover(isPresented: $showingOutfitCanvas) {
            NavigationStack {
                OutfitCanvasView(outfit: nil, initialItems: [item])
            }
        }
        .fullScreenCover(isPresented: $showingImageEditor) {
            if let imgName = item.imageFileName,
               let processed = imageService.loadImage(fileName: imgName) {
                let original = item.originalImageFileName
                    .flatMap { imageService.loadImage(fileName: $0) } ?? processed
                ImageEditorView(originalImage: original, editingImage: processed) { refined in
                    updateImage(refined)
                }
            }
        }
        .alert("永久删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("永久删除后不可恢复，确定要删除这件衣物吗？")
        }
    }

    @ViewBuilder
    private func headerImage() -> some View {
        if let image = loadHeaderImage() {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 350)
                .background(Color(.systemGray6))
        } else {
            ZStack {
                Color(.systemGray6)
                Image(systemName: "tshirt")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 350)
        }
    }

    private var idleDays: Int? {
        guard let lastWorn = item.lastWornDate else {
            // 从未穿过：计算从创建到现在的天数
            return Calendar.current.dateComponents([.day], from: item.createdAt, to: Date()).day
        }
        let days = Calendar.current.dateComponents([.day], from: lastWorn, to: Date()).day ?? 0
        return days > 14 ? days : nil  // 14天内不算闲置
    }

    @ViewBuilder
    private func wearCountBar() -> some View {
        HStack {
            Button {
                showingWearHistory = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                    Text("穿着次数：\(item.wearCount)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if let days = idleDays {
                HStack(spacing: 4) {
                    Image(systemName: "zzz")
                        .font(.caption2)
                    Text("闲置 \(days) 天")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingWearHistory) {
                NavigationStack {
                    wearHistoryList()
                        .navigationTitle("穿着记录")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showingWearHistory = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
    }

    @ViewBuilder
    private func wearHistoryList() -> some View {
        let records = item.wearRecordItems
            .compactMap(\.wearRecord)
            .sorted { $0.date > $1.date }

        if records.isEmpty {
            ContentUnavailableView {
                Label("暂无穿着记录", systemImage: "calendar")
            } description: {
                Text("在日历页面记录每天的穿搭")
            }
        } else {
            List(records, id: \.id) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ChineseDateFormatter.fullDateWeekday(record.date))
                            .font(.subheadline)
                        if let occasion = record.occasion {
                            Text(occasion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let mood = record.mood {
                        Text(mood)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tabSelector() -> some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, title in
                let isSelected = selectedTab == index
                Text(title)
                    .font(isSelected ? .headline : .subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                        }
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = index
                        }
                    }
            }
        }
    }

    // MARK: - 详情（紧凑表格预览态）

    @ViewBuilder
    private func detailContent() -> some View {
        VStack(spacing: 0) {
            // 标题 + 修改按钮
            HStack {
                Text("属性详情")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingEditSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                        Text("修改")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // 备注独占首行
            if let notes = item.notes, !notes.isEmpty {
                HStack {

                    Text(notes)
                        .font(.caption)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            // 两列网格表格
            let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

            LazyVGrid(columns: columns, spacing: 0) {
                let topCat = item.topCategory?.name ?? ""

                gridCell("分类", value: item.category?.name)
                gridColorCell()
                gridCell("状态", value: item.status)
                gridCell("存放位置", value: item.storageLocation)
                gridSeasonCell()
                gridCell("品牌", value: item.brand)
                gridCell("尺码", value: item.size)
                gridCell("材质", value: item.material)

                // 上衣、连体装：领型+袖长
                if topCat == "上衣" || topCat == "连体装" {
                    gridCell("领型", value: item.collarType)
                    gridCell("袖长", value: item.sleeveLength)
                }

                // 裤子：裤长
                if topCat == "裤子" {
                    gridCell("裤长", value: item.pantLength)
                }

                // 半身裙、连体装：裙长
                if topCat == "半身裙" || topCat == "连体装" {
                    gridCell("裙长", value: item.skirtLength)
                }

                // 鞋：跟高
                if topCat == "鞋" {
                    gridCell("跟高", value: item.heelHeight)
                }

                // 包：包型
                if topCat == "包" {
                    gridCell("包型", value: item.bagSize)
                }

                // 闭合方式（帽子/首饰/配饰不显示）
                if ["上衣", "裤子", "半身裙", "连体装", "鞋", "包"].contains(topCat) {
                    gridCell("闭合方式", value: item.closureType)
                }

                gridCell("洗涤方式", value: item.washingMethod)
                gridPriceCell()
                gridDateCell()
                gridCell("购买链接", value: item.purchaseLink)
            }
            .padding(.horizontal)

            // 标签单独一行（可能较长）
            if !item.tags.isEmpty {
                HStack(spacing: 0) {
                    Text("标签")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray6))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            showingEditSheet = true
        }
    }

    @ViewBuilder
    private func gridCell(_ title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value ?? "-")
                .font(.caption)
                .foregroundStyle(value == nil ? .quaternary : .primary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func gridColorCell() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("颜色")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                if !item.colorHexValues.isEmpty {
                    ColorDotView(hexValues: item.colorHexValues)
                }
                Text(item.colorStyle ?? "纯色")
                    .font(.caption)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func gridSeasonCell() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("季节")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if item.seasons.isEmpty {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            } else {
                Text(item.seasons.joined(separator: " "))
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func gridPriceCell() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("购买价格")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let price = item.purchasePrice {
                Text("¥\(price, specifier: "%.0f")")
                    .font(.caption)
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func gridDateCell() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("购买时间")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let date = item.purchaseDate {
                Text(ChineseDateFormatter.fullDate(date))
                    .font(.caption)
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - 其他 Tab

    @ViewBuilder
    private func outfitContent() -> some View {
        let outfits = item.outfitSlots.compactMap(\.outfit)
        if outfits.isEmpty {
            EmptyStateView(icon: "square.on.square", title: "暂无搭配", message: "去创建搭配吧")
                .padding(.top, 60)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(outfits, id: \.id) { outfit in
                    NavigationLink {
                        OutfitCanvasView(outfit: outfit)
                    } label: {
                        OutfitCardView(outfit: outfit)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func recommendContent() -> some View {
        ItemRecommendationView(item: item)
    }

    @ViewBuilder
    private func bottomBar() -> some View {
        HStack {
            Button {
                showingOutfitCanvas = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("创建搭配")
                        .font(.subheadline)
                }
            }

            Spacer()

            Button {
                item.isFavorite.toggle()
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(item.isFavorite ? .red : .secondary)
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// 编辑图片后更新文件 + 重新分析颜色
    private func updateImage(_ refined: UIImage) {
        Task {
            do {
                let original: UIImage
                if let origName = item.originalImageFileName,
                   let origImg = imageService.loadImage(fileName: origName) {
                    original = origImg
                } else {
                    original = refined
                }

                let oldImgFile = item.imageFileName
                let oldThumbFile = item.thumbnailFileName
                imageService.deleteImages(
                    imageFileName: oldImgFile,
                    originalFileName: nil,
                    thumbnailFileName: oldThumbFile
                )

                let result = try await imageService.saveImages(processed: refined, original: original)

                // 仅重新提取颜色（本地，不调用 LLM）
                let colors = await ClothingRecognitionService.shared.extractColors(from: refined)

                await MainActor.run {
                    item.imageFileName = result.imageFileName
                    item.thumbnailFileName = result.thumbnailFileName
                    if !colors.isEmpty {
                        item.colorHexValues = colors
                    }
                    modelContext.safeSave()
                }
            } catch {
                logger.error("图片编辑更新失败: \(error.localizedDescription)")
            }
        }
    }

    private func loadHeaderImage() -> UIImage? {
        if let thumbName = item.thumbnailFileName,
           let thumb = imageService.loadThumbnail(fileName: thumbName) {
            return thumb
        }
        if let imgName = item.imageFileName {
            return imageService.loadImage(fileName: imgName)
        }
        return nil
    }

    private func deleteItem() {
        let imgFile = item.imageFileName
        let origFile = item.originalImageFileName
        let thumbFile = item.thumbnailFileName
        item.cleanupBeforeDelete(in: modelContext)
        modelContext.delete(item)
        modelContext.safeSave()
        imageService.deleteImages(
            imageFileName: imgFile,
            originalFileName: origFile,
            thumbnailFileName: thumbFile
        )
        dismiss()
    }
}
