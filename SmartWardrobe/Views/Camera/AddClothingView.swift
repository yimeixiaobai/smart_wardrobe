import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

struct AddClothingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allClothingItems: [ClothingItem]

    var preselectedCategory: Category?
    var onSaved: ((ClothingItem) -> Void)?

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var originalImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var isProcessing = false
    @State private var processingError: String?
    @State private var showCamera = false
    @State private var showCameraPermissionAlert = false
    @State private var step: Step = .selectImage
    @State private var similarityResult: SimilarityCheckService.CheckResult?
    @State private var savingPhase: SavingPhase = .savingImage
    @State private var showingImageEditor = false
    @State private var untrimmedProcessed: UIImage?
    @State private var resizedOriginal: UIImage?

    enum Step {
        case selectImage
        case preview
        case checkingSimilarity
        case saving
    }

    var body: some View {
        NavigationStack {
            VStack {
                switch step {
                case .selectImage:
                    imageSelectionView()
                case .preview:
                    backgroundRemovalPreview()
                case .checkingSimilarity:
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在检查相似衣物...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .saving:
                    SavingProgressView(phase: savingPhase)
                }
            }
            .navigationTitle("添加衣物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(item: $similarityResult) { result in
                SimilarClothingResultView(
                    result: result,
                    newImage: processedImage,
                    onSaveAnyway: {
                        similarityResult = nil
                        saveClothing(skipSimilarityCheck: true)
                    },
                    onCancel: {
                        similarityResult = nil
                        step = .preview
                    }
                )
                .presentationDetents([.large])
            }
            .alert("处理失败", isPresented: .constant(processingError != nil)) {
                Button("重试") {
                    processingError = nil
                    if let img = originalImage {
                        processImage(img)
                    }
                }
                Button("跳过去背景") {
                    processingError = nil
                    processedImage = originalImage
                    step = .preview
                }
                Button("取消", role: .cancel) {
                    processingError = nil
                    step = .selectImage
                }
            } message: {
                Text(processingError ?? "")
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { image in
                    if let image {
                        originalImage = image.fixedOrientation()
                        processImage(image.fixedOrientation())
                    }
                }
            }
            .alert("无法访问相机", isPresented: $showCameraPermissionAlert) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在「设置 → 智能衣橱 → 相机」中开启权限")
            }
            .fullScreenCover(isPresented: $showingImageEditor) {
                if let resizedOrig = resizedOriginal,
                   let untrimmed = untrimmedProcessed {
                    ImageEditorView(
                        originalImage: resizedOrig,
                        editingImage: untrimmed
                    ) { refined in
                        // 编辑完成后裁剪透明边缘
                        processedImage = trimToOpaque(refined)
                        untrimmedProcessed = refined
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func imageSelectionView() -> some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "tshirt")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text("选择或拍摄衣物照片")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    checkCameraPermission()
                } label: {
                    Label("拍照", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            loadPhoto(from: newItem)
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在去除背景...")
                            .foregroundStyle(.white)
                    }
                    .padding(30)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    @ViewBuilder
    private func backgroundRemovalPreview() -> some View {
        VStack(spacing: 16) {
            Text("去背景预览")
                .font(.headline)

            HStack(spacing: 16) {
                VStack {
                    Text("原图")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let img = originalImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                VStack {
                    Text("去背景")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let img = processedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 250)
                            .background(
                                checkerboardPattern()
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    step = .selectImage
                    originalImage = nil
                    processedImage = nil
                    selectedPhotoItem = nil
                } label: {
                    Text("重选")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showingImageEditor = true
                } label: {
                    Text("编辑")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    checkSimilarityAndSave()
                } label: {
                    Text("保存")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func checkerboardPattern() -> some View {
        Canvas { context, size in
            let tileSize: CGFloat = 10
            for row in 0..<Int(size.height / tileSize) + 1 {
                for col in 0..<Int(size.width / tileSize) + 1 {
                    let isWhite = (row + col) % 2 == 0
                    let rect = CGRect(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize, width: tileSize, height: tileSize)
                    context.fill(Path(rect), with: .color(isWhite ? .white : Color(.systemGray5)))
                }
            }
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCamera = true }
                    else { showCameraPermissionAlert = true }
                }
            }
        default:
            showCameraPermissionAlert = true
        }
    }

    private func loadPhoto(from item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }
            let fixed = uiImage.fixedOrientation()
            originalImage = fixed
            processImage(fixed)
        }
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        Task {
            do {
                let result = try await BackgroundRemovalService.shared.removeBackgroundDetailed(from: image)
                await MainActor.run {
                    processedImage = result.trimmed
                    untrimmedProcessed = result.untrimmed
                    resizedOriginal = result.resizedOriginal
                    isProcessing = false
                    step = .preview
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    processingError = error.localizedDescription
                }
            }
        }
    }

    private func checkSimilarityAndSave() {
        guard let processed = processedImage else { return }
        step = .checkingSimilarity

        Task {
            let result = await SimilarityCheckService.shared.check(
                image: processed,
                against: allClothingItems,
                newItemCategory: preselectedCategory
            )

            await MainActor.run {
                if result.isEmpty {
                    saveClothing(skipSimilarityCheck: true)
                } else {
                    similarityResult = result
                }
            }
        }
    }

    private func saveClothing(skipSimilarityCheck: Bool = false) {
        guard let processed = processedImage, let original = originalImage else { return }
        step = .saving
        savingPhase = .savingImage

        Task {
            do {
                let input = ClothingItemFactory.SaveInput(
                    processedImage: processed,
                    originalImage: original,
                    preselectedCategory: preselectedCategory
                )
                let item = try await ClothingItemFactory.createAndSave(
                    input: input,
                    context: modelContext,
                    onPhaseChange: { savingPhase = $0 }
                )
                onSaved?(item)
                dismiss()
            } catch {
                processingError = "保存失败：\(error.localizedDescription)"
                step = .preview
            }
        }
    }

    /// 裁剪透明边缘（编辑完成后调用）
    private func trimToOpaque(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = cg.width, h = cg.height
        let bpp = 4
        var px = [UInt8](repeating: 0, count: w * h * bpp)
        guard let ctx = CGContext(
            data: &px, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * bpp,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                if px[(y * w + x) * bpp + 3] > 10 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard minX < maxX, minY < maxY else { return image }

        let pad = max(Int(Double(min(w, h)) * 0.02), 4)
        let rect = CGRect(
            x: max(0, minX - pad), y: max(0, minY - pad),
            width: min(w - max(0, minX - pad), maxX - minX + 2 * pad),
            height: min(h - max(0, minY - pad), maxY - minY + 2 * pad)
        )
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }
}

struct CameraView: UIViewControllerRepresentable {
    var onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onCapture(image)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
            picker.dismiss(animated: true)
        }
    }
}
