import SwiftUI
import PhotosUI

struct MannequinSetupView: View {
    @State private var referencePhoto: UIImage?
    @State private var keypoints: MannequinPhotoService.BodyKeypoints?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                photoPreview()
            }

            Section {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                }

                if referencePhoto != nil {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除照片", systemImage: "trash")
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("使用说明", systemImage: "info.circle")
                        .font(.subheadline.bold())
                    Text("1. 请选择一张全身正面照片")
                    Text("2. 双手自然下垂，手臂稍微离开身体")
                    Text("3. 背景简洁、光线充足效果更好")
                    Text("4. 照片仅保存在本地，不会上传")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let kp = keypoints {
                Section("检测结果") {
                    keypointStatus("头部", point: kp.nose)
                    keypointStatus("肩部", point: kp.shoulderCenter)
                    keypointStatus("髋部", point: kp.hipCenter)
                    keypointStatus("膝盖", point: kp.kneeCenter)
                    keypointStatus("脚踝", point: kp.ankleCenter)
                }
            }
        }
        .navigationTitle("模特照片")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在检测身体关键点...")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert("提示", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) { deletePhoto() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除模特照片后，搭配画布中将无法使用模特模式。")
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            processSelectedPhoto(newItem)
        }
        .task {
            await loadExisting()
        }
    }

    // MARK: - Photo Preview

    @ViewBuilder
    private func photoPreview() -> some View {
        if let photo = referencePhoto {
            GeometryReader { geo in
                let imageSize = photo.size
                let displaySize = fitSize(imageSize, in: geo.size)

                ZStack {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)

                    // Keypoint overlay
                    if let kp = keypoints {
                        keypointOverlay(kp, size: displaySize)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: 400)
            .listRowInsets(EdgeInsets())
        } else {
            VStack(spacing: 12) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 60))
                    .foregroundStyle(.tertiary)
                Text("尚未设置模特照片")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("选择全身照后，可在搭配画布中使用模特模式")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private func keypointOverlay(_ kp: MannequinPhotoService.BodyKeypoints, size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let joints: [(CGPoint?, Color)] = [
                (kp.nose, .blue),
                (kp.neck, .cyan),
                (kp.leftShoulder, .green), (kp.rightShoulder, .green),
                (kp.leftElbow, .yellow), (kp.rightElbow, .yellow),
                (kp.leftWrist, .orange), (kp.rightWrist, .orange),
                (kp.leftHip, .purple), (kp.rightHip, .purple),
                (kp.leftKnee, .pink), (kp.rightKnee, .pink),
                (kp.leftAnkle, .red), (kp.rightAnkle, .red),
                (kp.root, .white),
            ]

            // Draw skeleton lines
            let bones: [(CGPoint?, CGPoint?)] = [
                (kp.nose, kp.neck),
                (kp.neck, kp.leftShoulder), (kp.neck, kp.rightShoulder),
                (kp.leftShoulder, kp.leftElbow), (kp.leftElbow, kp.leftWrist),
                (kp.rightShoulder, kp.rightElbow), (kp.rightElbow, kp.rightWrist),
                (kp.neck, kp.root),
                (kp.root, kp.leftHip), (kp.root, kp.rightHip),
                (kp.leftHip, kp.leftKnee), (kp.leftKnee, kp.leftAnkle),
                (kp.rightHip, kp.rightKnee), (kp.rightKnee, kp.rightAnkle),
            ]

            for (a, b) in bones {
                guard let a, let b else { continue }
                let pa = CGPoint(x: a.x * size.width, y: a.y * size.height)
                let pb = CGPoint(x: b.x * size.width, y: b.y * size.height)
                // Offset to center in canvas
                let ox = (canvasSize.width - size.width) / 2
                let oy = (canvasSize.height - size.height) / 2
                var path = Path()
                path.move(to: CGPoint(x: pa.x + ox, y: pa.y + oy))
                path.addLine(to: CGPoint(x: pb.x + ox, y: pb.y + oy))
                context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 2)
            }

            // Draw joint dots
            for (point, color) in joints {
                guard let point else { continue }
                let x = point.x * size.width + (canvasSize.width - size.width) / 2
                let y = point.y * size.height + (canvasSize.height - size.height) / 2
                let rect = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func keypointStatus(_ name: String, point: CGPoint?) -> some View {
        HStack {
            Text(name)
            Spacer()
            if point != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("未检测到")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Actions

    private func processSelectedPhoto(_ item: PhotosPickerItem) {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    errorMessage = "无法加载所选照片"
                    return
                }

                let kp = try await MannequinPhotoService.shared.saveReferencePhoto(image)
                await MainActor.run {
                    referencePhoto = image
                    keypoints = kp
                    selectedPhotoItem = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePhoto() {
        Task {
            await MannequinPhotoService.shared.deleteReferencePhoto()
            await MainActor.run {
                referencePhoto = nil
                keypoints = nil
            }
        }
    }

    private func loadExisting() async {
        let service = MannequinPhotoService.shared
        let photo = await service.loadReferencePhoto()
        let kp = await service.loadKeypoints()
        await MainActor.run {
            referencePhoto = photo
            keypoints = kp
        }
    }

    // MARK: - Helpers

    private func fitSize(_ imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        let wRatio = containerSize.width / imageSize.width
        let hRatio = containerSize.height / imageSize.height
        let scale = min(wRatio, hRatio)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
