import SwiftUI
import UIKit

/// 图片编辑器：变换 + 精修合并为单页工具栏
struct ImageEditorView: View {
    let originalImage: UIImage
    @State var editingImage: UIImage
    let onDone: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    enum BrushMode {
        case none, erase, restore
    }

    @State private var brushMode: BrushMode = .none
    @State private var brushRadius: CGFloat = 15
    @State private var undoStack: [UIImage] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 图片预览区
                GeometryReader { geo in
                    ZStack {
                        checkerboard()

                        if brushMode != .none {
                            EraserCanvasView(
                                restoreSource: originalImage,
                                editingImage: $editingImage,
                                undoStack: $undoStack,
                                brushMode: brushMode,
                                brushRadius: brushRadius,
                                containerSize: geo.size
                            )
                        } else {
                            Image(uiImage: editingImage)
                                .resizable()
                                .scaledToFit()
                                .padding(16)
                        }
                    }
                }

                Divider()

                // 工具栏
                toolBar()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("编辑图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        onDone(editingImage)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private func toolBar() -> some View {
        VStack(spacing: 8) {
            // 画笔大小（仅擦除/恢复模式显示）
            if brushMode != .none {
                HStack(spacing: 8) {
                    Circle()
                        .fill(brushMode == .erase ? Color.red.opacity(0.5) : Color.green.opacity(0.5))
                        .frame(width: 10, height: 10)
                    Text("画笔").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $brushRadius, in: 5...50)
                    Text("\(Int(brushRadius))").font(.caption2).foregroundStyle(.secondary).frame(width: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // 工具按钮行
            HStack(spacing: 0) {
                toolButton(icon: "rotate.left", label: "左转") {
                    pushUndo(); editingImage = editingImage.rotated90CCW()
                }
                toolButton(icon: "rotate.right", label: "右转") {
                    pushUndo(); editingImage = editingImage.rotated90CW()
                }
                toolButton(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "翻转") {
                    pushUndo(); editingImage = editingImage.flippedHorizontally()
                }

                Divider().frame(height: 28).padding(.horizontal, 4)

                toolToggle(icon: "eraser", label: "擦除", mode: .erase)
                toolToggle(icon: "paintbrush.pointed", label: "恢复", mode: .restore)

                Divider().frame(height: 28).padding(.horizontal, 4)

                toolButton(icon: "arrow.uturn.backward", label: "撤销", disabled: undoStack.isEmpty) {
                    undo()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .animation(.easeInOut(duration: 0.2), value: brushMode)
    }

    @ViewBuilder
    private func toolButton(icon: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(height: 22)
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(disabled ? .quaternary : .primary)
            .frame(maxWidth: .infinity)
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toolToggle(icon: String, label: String, mode: BrushMode) -> some View {
        let isActive = brushMode == mode
        Button {
            withAnimation { brushMode = isActive ? .none : mode }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(height: 22)
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isActive ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func checkerboard() -> some View {
        Canvas { ctx, size in
            let tile: CGFloat = 10
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

    private func pushUndo() {
        undoStack.append(editingImage)
        if undoStack.count > 15 { undoStack.removeFirst() }
    }

    private func undo() {
        if let prev = undoStack.popLast() { editingImage = prev }
    }
}

// MARK: - Eraser Canvas (UIViewRepresentable)

struct EraserCanvasView: UIViewRepresentable {
    let restoreSource: UIImage
    @Binding var editingImage: UIImage
    @Binding var undoStack: [UIImage]
    let brushMode: ImageEditorView.BrushMode
    let brushRadius: CGFloat
    let containerSize: CGSize

    func makeUIView(context: Context) -> EraserUIView {
        let view = EraserUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = false
        view.restoreSource = restoreSource
        view.workingImage = editingImage
        updateViewProps(view)
        view.onStrokeStart = { [self] in
            undoStack.append(editingImage)
            if undoStack.count > 15 { undoStack.removeFirst() }
        }
        view.onStrokeEnd = { newImage in
            editingImage = newImage
        }
        return view
    }

    func updateUIView(_ uiView: EraserUIView, context: Context) {
        updateViewProps(uiView)
        if uiView.workingImage !== editingImage as UIImage? {
            uiView.workingImage = editingImage
            uiView.syncContext()
            uiView.setNeedsDisplay()
        }
    }

    private func updateViewProps(_ view: EraserUIView) {
        let imgSize = editingImage.size
        let fitted = fitSize(imgSize, in: containerSize, padding: 16)
        view.displaySize = fitted
        view.brushRadius = brushRadius
        view.isErasing = brushMode == .erase
    }

    private func fitSize(_ imageSize: CGSize, in container: CGSize, padding: CGFloat) -> CGSize {
        let avail = CGSize(width: container.width - padding * 2, height: container.height - padding * 2)
        let scale = min(avail.width / imageSize.width, avail.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

class EraserUIView: UIView {
    var restoreSource: UIImage?
    var workingImage: UIImage?
    var displaySize: CGSize = .zero
    var brushRadius: CGFloat = 15
    var isErasing = true
    var onStrokeStart: (() -> Void)?
    var onStrokeEnd: ((UIImage) -> Void)?

    private var bitmapContext: CGContext?
    private var imageWidth: Int = 0
    private var imageHeight: Int = 0
    private var strokeActive = false

    func syncContext() {
        guard let cg = workingImage?.cgImage,
              cg.width > 0, cg.height > 0 else { return }
        imageWidth = cg.width
        imageHeight = cg.height
        bitmapContext = CGContext(
            data: nil, width: imageWidth, height: imageHeight,
            bitsPerComponent: 8, bytesPerRow: imageWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        bitmapContext?.draw(cg, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    }

    private var imageOrigin: CGPoint {
        CGPoint(x: (bounds.width - displaySize.width) / 2,
                y: (bounds.height - displaySize.height) / 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bitmapContext == nil, workingImage != nil {
            syncContext()
            setNeedsDisplay()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if bitmapContext == nil { syncContext() }
        strokeActive = true
        onStrokeStart?()
        applyBrush(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, strokeActive else { return }
        applyBrush(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard strokeActive else { return }
        strokeActive = false
        if let cgImage = bitmapContext?.makeImage() {
            let result = UIImage(cgImage: cgImage)
            workingImage = result
            onStrokeEnd?(result)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func applyBrush(at viewPoint: CGPoint) {
        guard let ctx = bitmapContext, imageWidth > 0, displaySize.width > 0 else { return }
        let origin = imageOrigin
        let relX = viewPoint.x - origin.x
        let relY = viewPoint.y - origin.y
        let scaleX = CGFloat(imageWidth) / displaySize.width
        let scaleY = CGFloat(imageHeight) / displaySize.height
        let imgX = relX * scaleX
        let imgY = CGFloat(imageHeight) - relY * scaleY
        let r = brushRadius * scaleX
        let brushRect = CGRect(x: imgX - r, y: imgY - r, width: r * 2, height: r * 2)

        if isErasing {
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: brushRect)
            ctx.setBlendMode(.normal)
        } else {
            guard let origCG = restoreSource?.cgImage else { return }
            ctx.saveGState()
            ctx.addEllipse(in: brushRect)
            ctx.clip()
            ctx.draw(origCG, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            ctx.restoreGState()
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let bitmapCG = bitmapContext?.makeImage() else { return }
        let origin = imageOrigin
        let drawRect = CGRect(origin: origin, size: displaySize)
        UIImage(cgImage: bitmapCG).draw(in: drawRect)
    }

    override var intrinsicContentSize: CGSize { displaySize }
}
