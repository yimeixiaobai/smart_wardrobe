import SwiftUI
import SwiftData

struct OutfitCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var outfit: Outfit?
    var initialItems: [ClothingItem] = []

    @State private var currentOutfit: Outfit?
    @State private var slots: [CanvasSlot] = []
    @State private var selectedSlotId: UUID?
    @State private var backgroundStyleIndex = 0
    @State private var outfitName = ""
    @State private var pickerCategory: Category?
    @State private var navPickerActive = false
    @State private var showingColorHarmony = false
    @State private var scaleAtDragStart: CGFloat = 1.0
    @State private var isDraggingScaleHandle = false
    @State private var rotationAtGestureStart: Angle = .zero
    @State private var activeRotationSlotId: UUID?
    @State private var isDraggingRotateHandle = false
    @State private var magnifyStartScale: CGFloat = 1.0
    @State private var activeMagnifySlotId: UUID?
    @State private var rotateHandleStartAngle: Angle = .zero
    @State private var canvasMode: CanvasMode = .free
    @State private var mannequinPhoto: UIImage?
    @State private var mannequinLoaded = false
    @State private var bodyKeypoints: MannequinPhotoService.BodyKeypoints?
    @State private var mannequinOpacity: Double = 0.35
    @State private var showingMannequinSetup = false

    enum CanvasMode: String {
        case free = "自由"
        case mannequin = "模特"
    }

    @Query(filter: #Predicate<Category> { $0.parent == nil },
           sort: \Category.sortOrder)
    private var topCategories: [Category]

    struct CanvasSlot: Identifiable {
        var id = UUID()
        var item: ClothingItem
        var position: CGPoint
        var scale: CGFloat = 1.0
        var rotation: Angle = .zero
        var zIndex: Int = 0
    }

    var body: some View {
        VStack(spacing: 0) {
            nameField()
            if mannequinPhoto != nil {
                modeToggleBar()
            }
            categoryTabBar()
            canvas()
            bottomToolbar()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { saveOutfit() }
                    .fontWeight(.semibold)
            }
        }
        // 已有搭配（NavigationLink push）用 sheet
        .sheet(item: outfit != nil ? $pickerCategory : .constant(nil)) { category in
            NavigationStack {
                ClothingPickerView(category: category) { selectedItem in
                    addItemToCanvas(selectedItem)
                    pickerCategory = nil
                }
            }
        }
        // 新建搭配（fullScreenCover）用 navigationDestination
        .navigationDestination(isPresented: $navPickerActive) {
            ClothingPickerView(category: pickerCategory) { selectedItem in
                addItemToCanvas(selectedItem)
                navPickerActive = false
            }
        }
        .onChange(of: navPickerActive) { _, active in
            if !active { pickerCategory = nil }
        }
        .onAppear {
            loadExistingOutfit()
            loadInitialItems()
        }
        .alert("部分衣物已删除", isPresented: .constant(missingItemCount > 0)) {
            Button("知道了") { missingItemCount = 0 }
        } message: {
            Text("这套搭配中有 \(missingItemCount) 件衣物已被删除，已自动移除对应位置")
        }
        .task {
            guard !mannequinLoaded else { return }
            mannequinLoaded = true
            await loadMannequinData()
        }
    }

    @ViewBuilder
    private func modeToggleBar() -> some View {
        HStack(spacing: 12) {
            // 模式切换
            Picker("模式", selection: $canvasMode) {
                Text("自由").tag(CanvasMode.free)
                Text("模特").tag(CanvasMode.mannequin)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)

            Spacer()

            // 模特透明度调节
            if canvasMode == .mannequin {
                HStack(spacing: 4) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $mannequinOpacity, in: 0.1...0.8)
                        .frame(width: 90)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func nameField() -> some View {
        HStack {
            TextField("输入搭配名称", text: $outfitName)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func categoryTabBar() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(topCategories) { category in
                    Button {
                        pickerCategory = category
                        if outfit == nil {
                            navPickerActive = true
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.title3)
                            Text(category.name)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func canvas() -> some View {
        let bgColor = AppConstants.CanvasBackground.styles[backgroundStyleIndex].color

        GeometryReader { geometry in
            ZStack {
                bgColor
                    .onTapGesture {
                        selectedSlotId = nil
                    }

                // 模特背景
                if canvasMode == .mannequin, let photo = mannequinPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .opacity(mannequinOpacity)
                        .allowsHitTesting(false)
                }

                ForEach(slots) { slot in
                    canvasItem(slot: slot, canvasSize: geometry.size)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    @ViewBuilder
    private func canvasItem(slot: CanvasSlot, canvasSize: CGSize) -> some View {
        let isSelected = selectedSlotId == slot.id
        let imageService = ImageStorageService.shared

        Group {
            // 优先用缩略图（节省内存），仅在无缩略图时回退到全尺寸
            if let thumbName = slot.item.thumbnailFileName,
               let image = imageService.loadThumbnail(fileName: thumbName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let imgName = slot.item.imageFileName,
                      let image = imageService.loadImage(fileName: imgName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "tshirt")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 120 * slot.scale, height: 120 * slot.scale)
        .rotationEffect(slot.rotation)
        .overlay {
            if isSelected {
                selectionOverlay(slotId: slot.id)
            }
        }
        .position(canvasToScreen(slot.position, canvasSize: canvasSize))
        .zIndex(Double(slot.zIndex))
        .onTapGesture {
            selectedSlotId = slot.id
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard !isDraggingScaleHandle, !isDraggingRotateHandle,
                          let index = slots.firstIndex(where: { $0.id == slot.id }) else { return }
                    slots[index].position = screenToCanvas(value.location, canvasSize: canvasSize)
                    selectedSlotId = slot.id
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if activeMagnifySlotId != slot.id {
                        activeMagnifySlotId = slot.id
                        magnifyStartScale = slot.scale
                    }
                    guard let index = slots.firstIndex(where: { $0.id == slot.id }) else { return }
                    slots[index].scale = max(0.3, min(3.0, magnifyStartScale * value.magnification))
                }
                .onEnded { _ in
                    activeMagnifySlotId = nil
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .onChanged { angle in
                    if activeRotationSlotId != slot.id {
                        activeRotationSlotId = slot.id
                        rotationAtGestureStart = slot.rotation
                    }
                    guard let index = slots.firstIndex(where: { $0.id == slot.id }) else { return }
                    slots[index].rotation = rotationAtGestureStart + angle
                }
                .onEnded { _ in
                    activeRotationSlotId = nil
                }
        )
    }

    /// 浅色背景时用深边框，深色背景时用浅边框
    private var isLightBackground: Bool {
        backgroundStyleIndex < 4 // 前4个是浅色背景
    }

    @ViewBuilder
    private func selectionOverlay(slotId: UUID) -> some View {
        let borderColor = isLightBackground ? Color.accentColor : Color.white.opacity(0.8)

        ZStack {
            // 选中边框
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                .foregroundStyle(borderColor)
                .padding(-8)

            // 删除按钮 (左上)
            VStack {
                HStack {
                    Button {
                        removeSlot(id: slotId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.red)
                    }
                    .offset(x: -14, y: -14)
                    Spacer()
                }
                Spacer()
            }

            // 旋转手柄 (右上) — 可拖拽
            VStack {
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: "rotate.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .offset(x: 14, y: -14)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDraggingRotateHandle {
                                        isDraggingRotateHandle = true
                                        rotateHandleStartAngle = slots.first(where: { $0.id == slotId })?.rotation ?? .zero
                                    }
                                    let degrees = Double(value.translation.width) * 0.8
                                    guard let index = slots.firstIndex(where: { $0.id == slotId }) else { return }
                                    slots[index].rotation = rotateHandleStartAngle + .degrees(degrees)
                                }
                                .onEnded { _ in
                                    isDraggingRotateHandle = false
                                }
                        )
                }
                Spacer()
            }

            // 缩放手柄 (右下) — 可拖拽
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .offset(x: 14, y: 14)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDraggingScaleHandle {
                                        isDraggingScaleHandle = true
                                        scaleAtDragStart = slots.first(where: { $0.id == slotId })?.scale ?? 1.0
                                    }
                                    let delta = (value.translation.width + value.translation.height) / 150
                                    guard let index = slots.firstIndex(where: { $0.id == slotId }) else { return }
                                    slots[index].scale = max(0.3, min(3.0, scaleAtDragStart + delta))
                                }
                                .onEnded { _ in
                                    isDraggingScaleHandle = false
                                }
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func bottomToolbar() -> some View {
        VStack(spacing: 0) {
            // 配色栏：始终占位，避免删除衣物时 canvas 高度跳动
            if slots.count >= 2 {
                colorHarmonyBar()
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "paintpalette")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("添加 2 件以上查看配色分析")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
            }

            HStack(spacing: 30) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingColorHarmony.toggle()
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "paintpalette")
                        Text("配色")
                            .font(.caption2)
                    }
                    .foregroundStyle(slots.count >= 2 ? Color.accentColor : .secondary)
                }
                .disabled(slots.count < 2)

                Button {
                    backgroundStyleIndex = (backgroundStyleIndex + 1) % AppConstants.CanvasBackground.styles.count
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "paintbrush")
                        Text("背景")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                Button {
                    if mannequinPhoto != nil {
                        canvasMode = (canvasMode == .free) ? .mannequin : .free
                    } else {
                        showingMannequinSetup = true
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "figure.stand")
                        Text("模特")
                            .font(.caption2)
                    }
                    .foregroundStyle(canvasMode == .mannequin ? Color.accentColor : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingMannequinSetup, onDismiss: {
            // 设置完成后重新加载模特数据
            Task { await loadMannequinData() }
        }) {
            NavigationStack {
                MannequinSetupView()
            }
        }
    }

    @ViewBuilder
    private func colorHarmonyBar() -> some View {
        ColorHarmonyBarView(
            hexColorSets: slots.map { $0.item.colorHexValues },
            isExpanded: $showingColorHarmony
        )
    }

    private func addItemToCanvas(_ item: ClothingItem) {
        let canvasSize = CGSize(width: 400, height: 600)
        var position = CGPoint(x: 200, y: 300 + CGFloat(slots.count) * 30)
        var scale: CGFloat = 1.0
        var zIndex = slots.count

        if canvasMode == .mannequin, let kp = bodyKeypoints {
            let categoryName = item.topCategory?.name ?? ""
            let subcategory = item.category?.name ?? ""

            // 分析衣物图片锚点
            var clothingAnchors: MannequinPhotoService.ClothingAnchors?
            let imageService = ImageStorageService.shared
            if let imgName = item.imageFileName,
               let clothingImage = imageService.loadImage(fileName: imgName) {
                clothingAnchors = MannequinPhotoService.analyzeClothing(
                    image: clothingImage, categoryName: categoryName
                )
            }

            let guide = MannequinPhotoService.placementGuide(
                for: categoryName,
                subcategory: subcategory,
                keypoints: kp,
                canvasSize: canvasSize,
                clothingAnchors: clothingAnchors
            )
            position = CGPoint(
                x: guide.position.x * canvasSize.width,
                y: guide.position.y * canvasSize.height
            )
            scale = guide.scale
            zIndex = guide.zIndex
        }

        let newSlot = CanvasSlot(
            item: item,
            position: position,
            scale: scale,
            zIndex: zIndex
        )
        slots.append(newSlot)
    }

    private func removeSlot(id: UUID) {
        slots.removeAll { $0.id == id }
        if selectedSlotId == id {
            selectedSlotId = nil
        }
    }

    private func loadInitialItems() {
        guard outfit == nil, !initialItems.isEmpty, slots.isEmpty else { return }
        for (index, item) in initialItems.enumerated() {
            let slot = CanvasSlot(
                item: item,
                position: CGPoint(x: 200, y: 200 + CGFloat(index) * 80),
                zIndex: index
            )
            slots.append(slot)
        }
    }

    // MARK: - 坐标转换（标准 400×600 ↔ 实际画布大小）

    private static let canonicalSize = CGSize(width: 400, height: 600)

    private func canvasToScreen(_ point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(x: point.x / Self.canonicalSize.width * canvasSize.width,
                y: point.y / Self.canonicalSize.height * canvasSize.height)
    }

    private func screenToCanvas(_ point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(x: point.x / canvasSize.width * Self.canonicalSize.width,
                y: point.y / canvasSize.height * Self.canonicalSize.height)
    }

    @State private var missingItemCount = 0

    private func loadExistingOutfit() {
        guard let outfit, slots.isEmpty else { return }
        currentOutfit = outfit
        outfitName = outfit.name
        backgroundStyleIndex = AppConstants.CanvasBackground.styles.firstIndex(where: { $0.name == outfit.backgroundStyle }) ?? 0

        var missing = 0
        for slot in outfit.sortedSlots {
            guard let item = slot.clothingItem else {
                missing += 1
                continue
            }
            let canvasSlot = CanvasSlot(
                item: item,
                position: CGPoint(x: slot.positionX * 400, y: slot.positionY * 600),
                scale: slot.scale,
                rotation: .degrees(slot.rotation),
                zIndex: slot.zIndex
            )
            slots.append(canvasSlot)
        }
        missingItemCount = missing
    }

    private func loadMannequinData() async {
        let service = MannequinPhotoService.shared
        // 先只加载 keypoints（轻量），确认有模特照片后再按需加载图片
        guard await service.hasReferencePhoto() else { return }
        let kp = await service.loadKeypoints()
        // 缩小模特照片用于画布背景（max 800px，节省内存）
        let photo = await service.loadReferencePhoto()
        let small = photo?.resized(to: 800)
        await MainActor.run {
            mannequinPhoto = small
            bodyKeypoints = kp
        }
    }

    private func saveOutfit() {
        let target: Outfit
        if let existing = currentOutfit {
            target = existing
            // Clear old slots
            let oldSlots = target.slots
            for slot in oldSlots {
                modelContext.delete(slot)
            }
            target.slots = []
        } else {
            target = Outfit(name: outfitName.isEmpty ? "搭配 \(ChineseDateFormatter.monthDay(Date()))" : outfitName)
            modelContext.insert(target)
        }

        target.name = outfitName.isEmpty ? "搭配 \(ChineseDateFormatter.monthDay(Date()))" : outfitName
        target.backgroundStyle = AppConstants.CanvasBackground.styles[backgroundStyleIndex].name

        let canvasWidth: Double = 400
        let canvasHeight: Double = 600

        for slot in slots {
            let outfitSlot = OutfitSlot(
                clothingItem: slot.item,
                positionX: slot.position.x / canvasWidth,
                positionY: slot.position.y / canvasHeight,
                zIndex: slot.zIndex
            )
            outfitSlot.scale = slot.scale
            outfitSlot.rotation = slot.rotation.degrees
            modelContext.insert(outfitSlot)
            target.slots.append(outfitSlot)
        }

        // 自动取衣物季节交集
        let allSeasons = slots.map { Set($0.item.seasons) }
        if let first = allSeasons.first {
            let intersection = allSeasons.dropFirst().reduce(first) { $0.intersection($1) }
            target.seasons = intersection.isEmpty
                ? Array(allSeasons.reduce(Set<String>()) { $0.union($1) })  // 无交集取并集
                : Array(intersection)
        }

        // 删除旧缩略图文件
        if let oldThumb = target.thumbnailFileName {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Thumbnails", isDirectory: true)
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(oldThumb))
        }

        // 生成缩略图
        target.thumbnailFileName = generateThumbnail(for: target)

        modelContext.safeSave()
        dismiss()
    }

    private func generateThumbnail(for outfit: Outfit) -> String? {
        let bgColor = AppConstants.CanvasBackground.styles[backgroundStyleIndex].color
        let slotInfos = slots.map {
            ImageStorageService.CanvasSlotInfo(
                position: $0.position,
                scale: $0.scale,
                rotation: $0.rotation.degrees,
                zIndex: $0.zIndex,
                thumbnailFileName: $0.item.thumbnailFileName,
                imageFileName: $0.item.imageFileName
            )
        }
        return ImageStorageService.shared.generateOutfitThumbnail(
            slots: slotInfos, bgColor: UIColor(bgColor)
        )
    }
}

