import SwiftUI
import PhotosUI
import SwiftData

struct BatchImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allClothingItems: [ClothingItem]

    var preselectedCategory: Category?

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var tasks: [ImportTask] = []
    @State private var step: Step = .selectImages
    @State private var elapsedSeconds = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var editingIndex: Int?
    @State private var savingIndex = 0
    @State private var processingTask: Task<Void, Never>?

    enum Step {
        case selectImages
        case removingBg     // 只做去背景（快速）
        case preview        // 用户预览/编辑，手动点导入
        case saving         // 保存+AI识别
        case done
    }

    struct ImportTask: Identifiable {
        let id = UUID()
        let photoItem: PhotosPickerItem
        var phase: Phase = .pending
        var originalImage: UIImage?
        var processedImage: UIImage?
        var errorMessage: String?
        var included = true
        var isSimilar = false  // 与衣橱已有衣物相似

        enum Phase: String {
            case pending = "等待中"
            case removingBg = "去除背景"
            case checkingSimilar = "检查相似"
            case saving = "保存中"
            case recognizing = "AI 识别"
            case done = "完成"
            case failed = "失败"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .selectImages: selectView()
                case .removingBg:   removingBgView()
                case .preview:      previewView()
                case .saving:       savingView()
                case .done:         doneView()
                }
            }
            .navigationTitle("批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { editingIndex != nil },
                set: { if !$0 { editingIndex = nil } }
            )) {
                editorContent()
            }
            .onDisappear {
                processingTask?.cancel()
                processingTask = nil
                timerTask?.cancel()
                timerTask = nil
            }
        }
    }

    // MARK: - Step 1: Select

    @ViewBuilder
    private func selectView() -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("选择多张衣物照片")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("建议每张照片只包含一件衣物\n系统将自动去除背景")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            PhotosPicker(selection: $selectedItems, maxSelectionCount: 20, matching: .images) {
                Label("从相册选择 (\(selectedItems.count) 张)", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            if !selectedItems.isEmpty {
                Button {
                    startRemovingBg()
                } label: {
                    Label("开始处理", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    // MARK: - Step 2: Removing BG (fast)

    @ViewBuilder
    private func removingBgView() -> some View {
        let completed = tasks.filter { $0.phase != .pending && $0.phase != .removingBg }.count

        VStack(spacing: 16) {
            VStack(spacing: 10) {
                HStack {
                    Text("去除背景中")
                        .font(.headline)
                    Spacer()
                    Text("\(completed)/\(tasks.count)")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(Color.accentColor)
                }
                ProgressView(value: Double(completed), total: Double(tasks.count))
                    .tint(Color.accentColor)
                HStack {
                    Label("\(elapsedSeconds)s", systemImage: "clock")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if completed > 0 {
                        let remaining = Int(Double(elapsedSeconds) / Double(completed) * Double(tasks.count - completed))
                        Text("预计还需 ~\(remaining)s")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        bgTaskRow(task)
                    }
                }
                .padding(.horizontal)

                if completed < tasks.count {
                    LoadingTipsView()
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func bgTaskRow(_ task: ImportTask) -> some View {
        HStack(spacing: 12) {
            Group {
                if let img = task.processedImage ?? task.originalImage {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color(.systemGray5).overlay {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("照片 \(taskIndex(task) + 1)")
                .font(.subheadline)

            Spacer()

            switch task.phase {
            case .pending:
                Text("等待").font(.caption).foregroundStyle(.secondary)
            case .removingBg:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.7)
                    Text("去背景").font(.caption).foregroundStyle(.orange)
                }
            case .checkingSimilar:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.7)
                    Text("查重").font(.caption).foregroundStyle(.orange)
                }
            case .done:
                if task.isSimilar {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                        Text("可能重复").font(.caption)
                    }.foregroundStyle(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            case .failed:
                Text(task.errorMessage ?? "失败").font(.caption).foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Step 3: Preview Grid

    @ViewBuilder
    private func previewView() -> some View {
        let includedCount = tasks.filter { $0.included && $0.processedImage != nil }.count

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("预览去背景效果")
                    .font(.headline)
                Spacer()
                Text("\(includedCount) 件待导入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        if task.processedImage != nil {
                            previewCard(task: task, index: index)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }

            // Bottom bar
            VStack(spacing: 10) {
                Divider()
                Button {
                    startSaving()
                } label: {
                    Label("导入衣橱 (\(includedCount) 件)", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(includedCount > 0 ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(includedCount == 0)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private func previewCard(task: ImportTask, index: Int) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                // 棋盘格 + 去背景图
                checkerboard()
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        if let img = task.processedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                // 右上角操作按钮
                VStack(spacing: 6) {
                    // 勾选/取消
                    Button {
                        tasks[index].included.toggle()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(task.included ? Color.green : Color.black.opacity(0.3))
                                .frame(width: 26, height: 26)
                            Image(systemName: task.included ? "checkmark" : "")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    // 编辑
                    Button {
                        editingIndex = index
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 26, height: 26)
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(6)
            }

            // 底部标签
            HStack(spacing: 4) {
                if task.isSimilar {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(task.isSimilar ? "可能重复" : "照片 \(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(task.isSimilar ? Color.orange : (task.included ? Color.primary : Color.secondary))
            }
            .padding(.top, 4)
        }
        .opacity(task.included ? 1 : 0.4)
    }

    // MARK: - Step 4: Saving

    @ViewBuilder
    private func savingView() -> some View {
        let included = tasks.filter { $0.included && $0.processedImage != nil }
        let saved = included.filter { $0.phase == .done || $0.phase == .failed }.count

        VStack(spacing: 16) {
            VStack(spacing: 10) {
                HStack {
                    Text("正在导入")
                        .font(.headline)
                    Spacer()
                    Text("\(saved)/\(included.count)")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(Color.accentColor)
                }
                ProgressView(value: Double(saved), total: Double(included.count))
                    .tint(Color.accentColor)
                HStack {
                    Label("\(elapsedSeconds)s", systemImage: "clock")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    if saved > 0 {
                        let remaining = Int(Double(elapsedSeconds) / Double(saved) * Double(included.count - saved))
                        Text("预计还需 ~\(remaining)s").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        if task.included && task.processedImage != nil {
                            savingTaskRow(task)
                        }
                    }
                }
                .padding(.horizontal)

                LoadingTipsView()
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func savingTaskRow(_ task: ImportTask) -> some View {
        HStack(spacing: 12) {
            if let img = task.processedImage {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text("照片 \(taskIndex(task) + 1)").font(.subheadline)
            Spacer()
            switch task.phase {
            case .saving:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.7)
                    Text("保存").font(.caption).foregroundStyle(.orange)
                }
            case .recognizing:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.7)
                    Text("AI 识别").font(.caption).foregroundStyle(.orange)
                }
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Text("失败").font(.caption).foregroundStyle(.red)
            default:
                Text("等待").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Step 5: Done

    @ViewBuilder
    private func doneView() -> some View {
        let successCount = tasks.filter { $0.included && $0.phase == .done }.count
        let failedCount = tasks.filter { $0.included && $0.phase == .failed }.count
        let skippedCount = tasks.filter { !$0.included }.count

        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("导入完成").font(.title2.bold())
            VStack(spacing: 6) {
                Text("成功: \(successCount) 件").foregroundStyle(.green)
                if failedCount > 0 {
                    Text("失败: \(failedCount) 件").foregroundStyle(.red)
                }
                if skippedCount > 0 {
                    Text("未选: \(skippedCount) 件").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            Button { dismiss() } label: {
                Text("完成")
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.accentColor).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Editor Content

    @ViewBuilder
    private func editorContent() -> some View {
        if let idx = editingIndex, idx < tasks.count,
           let orig = tasks[idx].originalImage,
           let proc = tasks[idx].processedImage {
            let capturedIdx = idx
            ImageEditorView(originalImage: orig, editingImage: proc) { refined in
                tasks[capturedIdx].processedImage = refined
            }
        }
    }

    // MARK: - Checkerboard

    @ViewBuilder
    private func checkerboard() -> some View {
        Canvas { ctx, size in
            let tile: CGFloat = 8
            for row in 0..<Int(size.height / tile) + 1 {
                for col in 0..<Int(size.width / tile) + 1 {
                    let isWhite = (row + col) % 2 == 0
                    ctx.fill(
                        Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                        with: .color(isWhite ? .white : Color(.systemGray5))
                    )
                }
            }
        }
    }

    // MARK: - Logic

    private func taskIndex(_ task: ImportTask) -> Int {
        tasks.firstIndex(where: { $0.id == task.id }) ?? 0
    }

    // Phase 2: 只做去背景
    private func startRemovingBg() {
        tasks = selectedItems.map { ImportTask(photoItem: $0) }
        step = .removingBg
        elapsedSeconds = 0
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                elapsedSeconds += 1
            }
        }

        processingTask = Task {
            for index in tasks.indices {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    tasks[index].phase = .removingBg
                }
                do {
                    guard let data = try await tasks[index].photoItem.loadTransferable(type: Data.self),
                          let img = UIImage(data: data) else {
                        await MainActor.run {
                            tasks[index].phase = .failed
                            tasks[index].errorMessage = "无法读取"
                        }
                        continue
                    }
                    let fixed = img.fixedOrientation()
                    await MainActor.run { tasks[index].originalImage = fixed }

                    let processed: UIImage
                    do {
                        processed = try await BackgroundRemovalService.shared.removeBackground(from: fixed)
                    } catch {
                        processed = fixed // 去背景失败用原图
                    }
                    await MainActor.run {
                        tasks[index].processedImage = processed
                        tasks[index].phase = .checkingSimilar
                    }

                    // 相似度检查
                    let similarResult = await SimilarityCheckService.shared.check(
                        image: processed, against: allClothingItems
                    )
                    await MainActor.run {
                        tasks[index].isSimilar = !similarResult.isEmpty
                        tasks[index].phase = .done
                    }
                } catch {
                    await MainActor.run {
                        tasks[index].processedImage = tasks[index].originalImage
                        tasks[index].phase = .done
                    }
                }
            }

            await MainActor.run {
                timerTask?.cancel()
                timerTask = nil
                step = .preview
            }
        }
    }

    // Phase 4: 保存+识别
    private func startSaving() {
        step = .saving
        elapsedSeconds = 0
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                elapsedSeconds += 1
            }
        }

        // 重置所有待导入项的 phase，避免显示去背景阶段留下的 ✅
        for index in tasks.indices where tasks[index].included && tasks[index].processedImage != nil {
            tasks[index].phase = .pending
        }

        processingTask = Task {
            for index in tasks.indices {
                guard !Task.isCancelled else { break }
                guard tasks[index].included,
                      let processed = tasks[index].processedImage,
                      let original = tasks[index].originalImage else { continue }

                await MainActor.run { tasks[index].phase = .saving }

                do {
                    let input = ClothingItemFactory.SaveInput(
                        processedImage: processed,
                        originalImage: original,
                        preselectedCategory: preselectedCategory
                    )
                    _ = try await ClothingItemFactory.createAndSave(
                        input: input,
                        context: modelContext,
                        onPhaseChange: { phase in
                            if phase == .recognizing {
                                tasks[index].phase = .recognizing
                            }
                        }
                    )
                    tasks[index].phase = .done
                } catch {
                    tasks[index].phase = .failed
                    tasks[index].errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                timerTask?.cancel()
                timerTask = nil
                step = .done
            }
        }
    }
}
