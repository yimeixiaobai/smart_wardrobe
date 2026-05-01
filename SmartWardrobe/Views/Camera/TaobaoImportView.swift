import SwiftUI
import SwiftData
import PhotosUI
import WebKit

// MARK: - Main View

struct TaobaoImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var preselectedCategory: Category?

    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("导入方式", selection: $selectedTab) {
                    Text("淘口令").tag(0)
                    Text("截图识别").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                switch selectedTab {
                case 0:
                    TaokolingWebTab(preselectedCategory: preselectedCategory, onDismiss: { dismiss() })
                case 1:
                    ScreenshotTab(preselectedCategory: preselectedCategory, onDismiss: { dismiss() })
                default:
                    EmptyView()
                }
            }
            .navigationTitle("淘宝导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Tab 1: 淘口令 → WebView → JS提取 → 保存

private struct TaokolingWebTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allClothingItems: [ClothingItem]
    let preselectedCategory: Category?
    let onDismiss: () -> Void

    @State private var inputText = ""
    @State private var targetURL: URL?
    @State private var extractedInfo: TaobaoParserService.ProductInfo?
    @State private var processedImage: UIImage?
    @State private var errorMessage: String?
    @State private var step: Step = .input
    @State private var isExtracting = false
    @State private var similarityResult: SimilarityCheckService.CheckResult?
    @State private var savingPhase: SavingPhase = .savingImage

    // 多图选择器
    @State private var pendingExtractInfo: TaobaoParserService.ProductInfo?
    @State private var showingImagePicker = false
    @State private var webViewSnapshot: UIImage?
    @State private var showGuide = true
    @State private var showingImageEditor = false

    enum Step {
        case input       // 粘贴淘口令
        case webView     // 浏览商品页
        case preview     // 预览确认
        case checkingSimilarity
        case saving      // 保存中
    }

    var body: some View {
        Group {
            switch step {
            case .input:
                inputView()
            case .webView:
                webViewStep()
            case .preview:
                previewView()
            case .checkingSimilarity:
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5)
                    Text("正在检查相似衣物...").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .saving:
                SavingProgressView(phase: savingPhase)
            }
        }
        .sheet(item: $similarityResult) { result in
            SimilarClothingResultView(
                result: result,
                newImage: processedImage ?? extractedInfo?.image,
                onSaveAnyway: {
                    similarityResult = nil
                    saveProduct(skipSimilarityCheck: true)
                },
                onCancel: {
                    similarityResult = nil
                    step = .preview
                }
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showingImageEditor) {
            if let original = extractedInfo?.image, let processed = processedImage {
                ImageEditorView(originalImage: original, editingImage: processed) { refined in
                    processedImage = refined
                }
            }
        }
    }

    // MARK: Step 1 - 粘贴淘口令

    @ViewBuilder
    private func inputView() -> some View {
        VStack(spacing: 0) {
            // 步骤引导
            VStack(alignment: .leading, spacing: 10) {
                Text("如何导入")
                    .font(.subheadline.bold())
                guideStepRow(1, "在淘宝App打开商品，点「分享」复制链接")
                guideStepRow(2, "回到这里粘贴文本，点「打开商品页」")
                guideStepRow(3, "浏览到想要的图片，点页面上的「导入衣橱」")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // 粘贴区域
            VStack(spacing: 12) {
                TextEditor(text: $inputText)
                    .frame(height: 90)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        Group {
                            if inputText.isEmpty {
                                Text("粘贴淘宝/天猫商品分享文本...")
                                    .foregroundStyle(.quaternary)
                                    .padding(.leading, 12)
                                    .padding(.top, 16)
                                    .allowsHitTesting(false)
                            }
                        }, alignment: .topLeading
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )

                HStack(spacing: 12) {
                    Button {
                        if let clip = UIPasteboard.general.string {
                            inputText = clip
                        }
                    } label: {
                        Label("粘贴剪贴板", systemImage: "doc.on.clipboard")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        openInWebView()
                    } label: {
                        Label("打开商品页", systemImage: "safari")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(inputText.isEmpty ? Color(.systemGray4) : Color.accentColor)
                            .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(inputText.isEmpty)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func guideStepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Step 2 - WebView 浏览

    @ViewBuilder
    private func webViewStep() -> some View {
        ZStack {
            if let url = targetURL {
                TaobaoWebView(url: url, onExtract: { info, snapshot in
                    handleExtractedOrShowPicker(info, snapshot: snapshot)
                })
                .ignoresSafeArea(edges: .bottom)
            }

            VStack(spacing: 0) {
                // 顶部操作提示
                if showGuide {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.point.up.left")
                            .foregroundStyle(Color.accentColor)
                        Text("浏览商品，滑到想要的图片后点右上角「导入衣橱」")
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        Button {
                            withAnimation { showGuide = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // 底部返回 + loading
                HStack {
                    Button {
                        step = .input
                        targetURL = nil
                        pendingExtractInfo = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.bold())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }

                    Spacer()

                    if isExtracting {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // 多图选择器
            if showingImagePicker, let pending = pendingExtractInfo {
                imagePickerOverlay(pending)
            }
        }
    }

    /// 弹出图片选择器，让用户从自动检测的图片或截图中选择
    private func handleExtractedOrShowPicker(_ info: TaobaoParserService.ProductInfo, snapshot: UIImage?) {
        webViewSnapshot = snapshot
        pendingExtractInfo = info
        showingImagePicker = true
    }

    /// 用户从候选图中选了某一张
    private func selectImageFromPicker(url: URL) {
        guard var info = pendingExtractInfo else { return }
        info.imageURL = url
        showingImagePicker = false
        pendingExtractInfo = nil
        webViewSnapshot = nil
        handleExtracted(info)
    }

    /// 用户选择了截取的当前画面
    private func selectScreenshotFromPicker() {
        guard var info = pendingExtractInfo, let snapshot = webViewSnapshot else { return }
        info.image = snapshot
        info.imageURL = nil
        showingImagePicker = false
        pendingExtractInfo = nil
        webViewSnapshot = nil
        handleExtracted(info)
    }

    @ViewBuilder
    private func imagePickerOverlay(_ info: TaobaoParserService.ProductInfo) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                // 顶部标题
                HStack {
                    Text("选择商品图片")
                        .font(.headline)
                    Spacer()
                    Button("取消") {
                        showingImagePicker = false
                        pendingExtractInfo = nil
                        webViewSnapshot = nil
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()

                Divider()

                ScrollView {
                    let cdnURLs = info.imageURLs.filter { url in
                        let host = url.host?.lowercased() ?? ""
                        return host.contains("alicdn") || host.contains("tbcdn") || host.contains("taobaocdn")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        // 截取当前画面选项
                        if let snapshot = webViewSnapshot {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "camera.viewfinder")
                                        .foregroundStyle(Color.accentColor)
                                    Text("截取当前画面")
                                        .font(.subheadline.bold())
                                }
                                .foregroundStyle(.secondary)

                                Image(uiImage: snapshot)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.accentColor, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        selectScreenshotFromPicker()
                                    }
                                Text("没找到想要的图？返回后滑到目标轮播图再点导入")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        // 自动检测的商品图（横向滚动，加载失败的自动隐藏）
                        if !cdnURLs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("检测到的商品图")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(cdnURLs, id: \.absoluteString) { url in
                                            CDNImageCell(url: url) {
                                                selectImageFromPicker(url: url)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 空状态
                        if cdnURLs.isEmpty && webViewSnapshot == nil {
                            Text("未检测到商品图片，请返回后滑到目标图片再试")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 420)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
        }
        .background(Color.black.opacity(0.3).ignoresSafeArea())
    }

    // MARK: Step 3 - 预览确认

    @ViewBuilder
    private func previewView() -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // 商品图
                if let img = processedImage ?? extractedInfo?.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .background(checkerboard())
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(height: 200)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                Text("未获取到商品图片")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                }

                // 去背景状态
                if processedImage == nil, extractedInfo?.image != nil {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("正在去除背景...").font(.caption).foregroundStyle(.secondary)
                    }
                }

                // 商品信息
                VStack(alignment: .leading, spacing: 10) {
                    if let title = extractedInfo?.title, !title.isEmpty {
                        HStack(alignment: .top) {
                            Text("商品名").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                            Text(title).font(.subheadline)
                        }
                    }
                    if let price = extractedInfo?.price {
                        HStack {
                            Text("价格").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                            Text("¥\(price, specifier: "%.2f")").font(.subheadline.bold()).foregroundStyle(.red)
                        }
                    }
                    if let url = extractedInfo?.sourceURL {
                        HStack(alignment: .top) {
                            Text("来源").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                            Text(url.host ?? url.absoluteString).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 12) {
                    Button {
                        step = .webView
                        extractedInfo = nil
                        processedImage = nil
                    } label: {
                        Text("重选")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if processedImage != nil {
                        Button { showingImageEditor = true } label: {
                            Text("编辑")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Button { checkSimilarityAndSave() } label: {
                        Text("保存")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if let error = errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

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

    // MARK: Logic

    private func checkSimilarityAndSave() {
        let imageToCheck = processedImage ?? extractedInfo?.image
        guard let imageToCheck else {
            saveProduct(skipSimilarityCheck: true)
            return
        }

        step = .checkingSimilarity
        Task {
            let result = await SimilarityCheckService.shared.check(
                image: imageToCheck,
                against: allClothingItems,
                newItemCategory: preselectedCategory
            )
            await MainActor.run {
                if result.isEmpty {
                    saveProduct(skipSimilarityCheck: true)
                } else {
                    similarityResult = result
                }
            }
        }
    }

    private func openInWebView() {
        let parser = TaobaoParserService.shared
        guard let url = parser.extractURL(from: inputText) else {
            errorMessage = "未检测到有效的淘宝/天猫链接"
            return
        }
        errorMessage = nil

        // 从淘口令中预提取标题（作为备用）
        let preTitle = parser.extractTitle(from: inputText)

        targetURL = url
        extractedInfo = TaobaoParserService.ProductInfo(title: preTitle, sourceURL: url)
        step = .webView
    }

    private func handleExtracted(_ info: TaobaoParserService.ProductInfo) {
        isExtracting = true

        // 合并信息：淘口令预提取标题优先（JS在移动端常拿到"商品详情"等垃圾值）
        var merged = info
        let junkTitles = ["商品详情", "淘宝", "天猫", "登录", "手机淘宝", ""]
        let jsTitle = merged.title ?? ""
        if let preTitle = extractedInfo?.title, !preTitle.isEmpty {
            // 淘口令标题有效，优先使用
            merged.title = preTitle
        } else if junkTitles.contains(jsTitle) {
            // JS 拿到的是垃圾值，清空
            merged.title = nil
        }
        merged.sourceURL = extractedInfo?.sourceURL ?? info.sourceURL

        Task {
            // 下载商品图
            if let imgURL = merged.imageURL, merged.image == nil {
                if let (data, _) = try? await URLSession.shared.data(from: imgURL) {
                    merged.image = UIImage(data: data)
                }
            }

            await MainActor.run {
                extractedInfo = merged
                isExtracting = false
                step = .preview
            }

            // 后台去背景
            if let originalImage = merged.image {
                if let processed = try? await BackgroundRemovalService.shared.removeBackground(from: originalImage) {
                    await MainActor.run {
                        processedImage = processed
                    }
                }
            }
        }
    }

    private func saveProduct(skipSimilarityCheck: Bool = false) {
        let image = processedImage ?? extractedInfo?.image
        guard let image else {
            let item = ClothingItem()
            item.name = extractedInfo?.title ?? ""
            item.purchasePrice = extractedInfo?.price
            item.purchaseDate = Date()
            item.purchaseLink = extractedInfo?.sourceURL?.absoluteString
            item.category = preselectedCategory
            modelContext.insert(item)
            modelContext.safeSave()
            onDismiss()
            return
        }

        step = .saving
        savingPhase = .savingImage
        Task {
            do {
                let input = ClothingItemFactory.SaveInput(
                    processedImage: image,
                    originalImage: extractedInfo?.image ?? image,
                    preselectedCategory: preselectedCategory,
                    name: extractedInfo?.title ?? "",
                    purchasePrice: extractedInfo?.price,
                    purchaseDate: Date(),
                    purchaseLink: extractedInfo?.sourceURL?.absoluteString
                )
                _ = try await ClothingItemFactory.createAndSave(
                    input: input,
                    context: modelContext,
                    onPhaseChange: { savingPhase = $0 }
                )
                onDismiss()
            } catch {
                errorMessage = "保存失败: \(error.localizedDescription)"
                step = .preview
            }
        }
    }
}

// MARK: - CDN Image Cell (auto-hides on load failure)

/// 单个 CDN 商品图格子：加载失败时自动隐藏，不留空白
private struct CDNImageCell: View {
    let url: URL
    let onTap: () -> Void
    @State private var loadFailed = false

    var body: some View {
        if !loadFailed {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    Color.clear.onAppear { loadFailed = true }
                default:
                    Color(.systemGray6)
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
    }
}

// MARK: - WKWebView 封装

struct TaobaoWebView: UIViewRepresentable {
    let url: URL
    let onExtract: (TaobaoParserService.ProductInfo, UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExtract: onExtract)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // 注入提取按钮脚本
        let buttonScript = WKUserScript(
            source: Coordinator.floatingButtonJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(buttonScript)
        config.userContentController.add(context.coordinator, name: "taobaoExtract")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.allowsBackForwardNavigationGestures = true

        webView.load(URLRequest(url: url))
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "taobaoExtract")
        uiView.navigationDelegate = nil
        coordinator.webView = nil
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onExtract: (TaobaoParserService.ProductInfo, UIImage?) -> Void
        weak var webView: WKWebView?

        init(onExtract: @escaping (TaobaoParserService.ProductInfo, UIImage?) -> Void) {
            self.onExtract = onExtract
        }

        /// 页面加载完成后注入浮窗提取按钮
        /// 图片提取改为收集 **所有** 候选商品图，送回 Swift 端让用户选择
        static var floatingButtonJS: String {
            """
            (function() {
                if (document.getElementById('sw-extract-btn')) return;

                // ===== 注入 CSS：隐藏淘宝「前往手淘」/「打开APP」跳转横幅 =====
                var hideStyle = document.createElement('style');
                hideStyle.textContent =
                    '[class*="open-app"], [class*="openApp"], [class*="Open-App"],' +
                    '[class*="download-bar"], [class*="downloadBar"],' +
                    '[class*="go-app"], [class*="goApp"],' +
                    '[class*="smart-banner"], [class*="smartBanner"],' +
                    '[class*="app-download"], [class*="appDownload"],' +
                    '[class*="guide-app"], [class*="guideApp"],' +
                    '[class*="jump-app"], [class*="jumpApp"],' +
                    '[class*="open-tb"], [class*="openTb"],' +
                    '[class*="footerBar"], [class*="footer-bar"],' +
                    '[id*="J_openApp"], [id*="J_DlgOpen"]' +
                    '{ display:none !important; opacity:0 !important; pointer-events:none !important; height:0 !important; }';
                document.head.appendChild(hideStyle);

                // ===== 浮动按钮（放在顶部右侧，避开底部淘宝横幅） =====
                var btn = document.createElement('div');
                btn.id = 'sw-extract-btn';
                btn.innerHTML = '📥 导入衣橱';
                btn.style.cssText = 'position:fixed; top:80px; right:12px; z-index:99999; ' +
                    'background:linear-gradient(135deg,#ff6b35,#ff2d55); color:white; ' +
                    'padding:10px 16px; border-radius:22px; font-size:14px; font-weight:bold; ' +
                    'box-shadow:0 4px 15px rgba(255,45,85,0.4); cursor:pointer; ' +
                    'user-select:none; -webkit-user-select:none; ' +
                    'transition:transform 0.2s; letter-spacing:1px;';

                document.body.appendChild(btn);

                // Intercept ALL touch/click events on the button at window capture phase.
                // This fires BEFORE Taobao's global handlers and prevents app redirects.
                var _swTouched = false;
                ['touchstart','touchmove','touchend','touchcancel','click',
                 'pointerdown','pointerup','mousedown','mouseup'].forEach(function(evtName) {
                    window.addEventListener(evtName, function(e) {
                        var t = e.target;
                        if (!t) return;
                        if (t.id === 'sw-extract-btn' || (t.closest && t.closest('#sw-extract-btn'))) {
                            e.stopImmediatePropagation();
                            e.preventDefault();
                            if (evtName === 'touchstart') {
                                _swTouched = true;
                                btn.style.transform = 'scale(0.92)';
                            }
                            if (evtName === 'touchend') {
                                btn.style.transform = 'scale(1)';
                                beginExtract();
                            }
                            // Desktop fallback: only handle click if no touch event fired
                            if (evtName === 'click' && !_swTouched) {
                                beginExtract();
                            }
                            if (evtName === 'click') { _swTouched = false; }
                        }
                    }, true); // <-- capture phase
                });

                // ===== 入口：直接从当前位置提取（不滚动，保留用户选的轮播图） =====
                var _swExtracting = false;
                function beginExtract() {
                    if (_swExtracting) return;
                    _swExtracting = true;
                    btn.style.display = 'none';
                    setTimeout(doExtract, 500);
                }

                function doExtract() {
                    var result = { title: null, price: null, imageURLs: [] };

                    // ===== 标题 =====
                    var ogTitle = document.querySelector('meta[property="og:title"]');
                    if (ogTitle) result.title = ogTitle.getAttribute('content');
                    if (!result.title) result.title = document.title || '';
                    result.title = result.title.replace(/-淘宝网$/,'').replace(/-天猫.*$/,'').replace(/-tmall\\.com$/,'').trim();

                    var junkTitles = ['商品详情', '淘宝', '天猫', '登录', '手机淘宝', '拼多多', ''];
                    if (junkTitles.indexOf(result.title) >= 0) {
                        var nameSelectors = [
                            '[class*="ItemHeader--mainTitle"]', '[class*="title--title"]',
                            '[class*="productTitle"]', '[class*="tbTitle"]',
                            '[class*="mainTitle"]', '.tb-main-title', '#J_Title h3'
                        ];
                        result.title = null;
                        for (var k = 0; k < nameSelectors.length; k++) {
                            try {
                                var el = document.querySelector(nameSelectors[k]);
                                if (el && el.textContent.trim().length > 2) {
                                    result.title = el.textContent.trim();
                                    break;
                                }
                            } catch(e) {}
                        }
                    }

                    // ===== 价格 =====
                    var priceEls = document.querySelectorAll(
                        '[class*="rice"], [class*="amount"], .tm-price, [class*="Price"]'
                    );
                    for (var i = 0; i < priceEls.length; i++) {
                        var t = priceEls[i].textContent || '';
                        var m = t.match(/(\\d+\\.?\\d{0,2})/);
                        if (m && parseFloat(m[1]) > 0.1 && parseFloat(m[1]) < 100000) {
                            result.price = m[1];
                            break;
                        }
                    }
                    if (!result.price) {
                        var bodyText = document.body ? document.body.innerText : '';
                        var pm = bodyText.match(/[¥￥]\\s*(\\d+\\.?\\d{0,2})/);
                        if (pm) result.price = pm[1];
                    }

                    // ===== 收集所有候选商品图（去重） =====
                    result.imageURLs = collectAllProductImages();

                    window.webkit.messageHandlers.taobaoExtract.postMessage(JSON.stringify(result));
                    setTimeout(function() {
                        btn.innerHTML = '📥 导入衣橱';
                        btn.style.display = '';
                        _swExtracting = false;
                    }, 2000);
                }

                // ========== 多图收集 ==========

                function getImgURL(img) {
                    return img.src ||
                        img.getAttribute('data-src') ||
                        img.getAttribute('data-lazy-src') ||
                        img.getAttribute('data-original') ||
                        img.getAttribute('data-ks-lazyload') ||
                        img.getAttribute('data-lazyload-src') ||
                        img.getAttribute('data-ob-src') ||
                        (img.srcset ? img.srcset.split(',').pop().trim().split(' ')[0] : '') ||
                        '';
                }

                function isProductImg(url) {
                    if (!url || url.length < 10 || url.startsWith('data:')) return false;
                    var lower = url.toLowerCase();
                    var exclude = ['icon', 'logo', 'avatar', '.gif', 'loading', 'placeholder',
                                   'sprite', '1x1', 'blank', 'search', 'login', 'qrcode',
                                   'footer', 'header', 'nav-', 'badge', 'tag-', 'btn-'];
                    for (var i = 0; i < exclude.length; i++) {
                        if (lower.indexOf(exclude[i]) >= 0) return false;
                    }
                    // Reject small thumbnails by URL size hint (e.g. _60x60, _100x100)
                    var sm = url.match(/_(\\d+)x(\\d+)/);
                    if (sm && (parseInt(sm[1]) < 150 || parseInt(sm[2]) < 150)) return false;
                    return true;
                }

                function fixURL(url) {
                    if (!url) return null;
                    url = url.trim();
                    if (url.startsWith('//')) url = 'https:' + url;
                    if (!url.startsWith('http')) return null;
                    return url;
                }

                function isCDN(url) {
                    return url && (url.indexOf('alicdn.com') >= 0 ||
                                   url.indexOf('tbcdn.cn') >= 0 ||
                                   url.indexOf('taobaocdn.com') >= 0);
                }

                /// 去重辅助：把 URL 归一化到同一基础路径
                function urlKey(url) {
                    return url.replace(/_(\\d+)x(\\d+)[^/]*$/, '').replace(/\\?.*$/, '').toLowerCase();
                }

                function collectAllProductImages() {
                    var seen = {};
                    var urls = [];

                    function add(rawUrl) {
                        var u = fixURL(rawUrl);
                        if (!u || !isProductImg(u)) return;
                        if (!isCDN(u)) return;  // Only CDN images (alicdn/tbcdn) are real product images
                        var key = urlKey(u);
                        if (seen[key]) return;
                        seen[key] = true;
                        urls.push(u);
                    }

                    // 0. Currently visible images in viewport (captures the active carousel slide)
                    var vpW = window.innerWidth;
                    var vpH = window.innerHeight;
                    var visibleImgs = [];
                    document.querySelectorAll('img').forEach(function(img) {
                        var rect = img.getBoundingClientRect();
                        if (rect.top >= vpH || rect.bottom <= 0 || rect.left >= vpW || rect.right <= 0) return;
                        var visArea = Math.max(0, Math.min(rect.right, vpW) - Math.max(rect.left, 0)) *
                                      Math.max(0, Math.min(rect.bottom, vpH) - Math.max(rect.top, 0));
                        var src = getImgURL(img);
                        if (visArea > 20000 && src && isProductImg(src)) {
                            visibleImgs.push({ url: src, area: visArea });
                        }
                    });
                    visibleImgs.sort(function(a, b) { return b.area - a.area; });
                    for (var vi = 0; vi < visibleImgs.length; vi++) {
                        add(visibleImgs[vi].url);
                    }

                    // Also check visible CSS background-images (some carousels use bg-image)
                    var bgContainers = document.querySelectorAll(
                        '[class*="gallery"], [class*="Gallery"], [class*="slider"], [class*="Slider"],' +
                        '[class*="swiper"], [class*="Swiper"], [class*="carousel"], [class*="Carousel"],' +
                        '[class*="banner"], [class*="Banner"]'
                    );
                    bgContainers.forEach(function(el) {
                        var rect = el.getBoundingClientRect();
                        if (rect.top >= vpH || rect.bottom <= 0) return;
                        var children = [el].concat(Array.from(el.querySelectorAll('*')).slice(0, 30));
                        for (var ci = 0; ci < children.length; ci++) {
                            var bg = window.getComputedStyle(children[ci]).backgroundImage || '';
                            var bm = bg.match(/url\\(["']?(.*?)["']?\\)/);
                            if (bm && bm[1]) add(bm[1]);
                        }
                    });

                    // 1. og:image
                    var ogImg = document.querySelector('meta[property="og:image"]');
                    if (ogImg) {
                        var ogUrl = (ogImg.getAttribute('content') || '').trim();
                        if (ogUrl && isCDN(fixURL(ogUrl) || '')) add(ogUrl);
                    }

                    // 2. 主图轮播选择器（优先级最高，涵盖轮播的所有图）
                    var gallerySelectors = [
                        '[class*="PicGallery"] img', '[class*="picGallery"] img',
                        '[class*="slider"] img', '[class*="Slider"] img',
                        '[class*="swiper"] img', '[class*="Swiper"] img',
                        '[class*="gallery"] img', '[class*="Gallery"] img',
                        '[class*="mainPic"] img', '[class*="MainPic"] img',
                        '[class*="main-pic"] img', '[class*="mainImg"] img',
                        '[class*="MainImg"] img', '[class*="ItemHeader"] img',
                        '[class*="detailGallery"] img', '[class*="itemImg"] img',
                        '[class*="ItemImg"] img', '[class*="heroImage"] img',
                        '[class*="productImage"] img', '[class*="ProductImage"] img',
                        '#J_ImgBooth', '.tb-main-pic img', '.main-image img'
                    ];
                    for (var i = 0; i < gallerySelectors.length; i++) {
                        try {
                            var imgs = document.querySelectorAll(gallerySelectors[i]);
                            for (var j = 0; j < imgs.length; j++) {
                                add(getImgURL(imgs[j]));
                            }
                        } catch(e) {}
                    }

                    // 3. CSS background-image 容器
                    var bgSelectors = [
                        '[class*="PicGallery"]', '[class*="picGallery"]',
                        '[class*="slider"]', '[class*="Slider"]',
                        '[class*="swiper"]', '[class*="Swiper"]',
                        '[class*="gallery"]', '[class*="Gallery"]',
                        '[class*="mainPic"]', '[class*="MainPic"]',
                        '[class*="ItemHeader"]', '[class*="heroImage"]'
                    ];
                    for (var i = 0; i < bgSelectors.length; i++) {
                        try {
                            var containers = document.querySelectorAll(bgSelectors[i]);
                            for (var j = 0; j < containers.length; j++) {
                                var elems = [containers[j]].concat(
                                    Array.from(containers[j].querySelectorAll('*')).slice(0, 50)
                                );
                                for (var k = 0; k < elems.length; k++) {
                                    var cs = window.getComputedStyle(elems[k]);
                                    var bgStr = cs.backgroundImage || '';
                                    var m = bgStr.match(/url\\(["']?(.*?)["']?\\)/);
                                    if (m && m[1]) add(m[1]);
                                }
                            }
                        } catch(e) {}
                    }

                    // 4. 所有 CDN 域名的 img（按面积降序，取 top 15）
                    var cdnImgs = [];
                    document.querySelectorAll('img').forEach(function(img) {
                        var s = getImgURL(img);
                        if (!s || !isProductImg(s) || !isCDN(s)) return;
                        var w = img.naturalWidth || img.width || 0;
                        var h = img.naturalHeight || img.height || 0;
                        var area = w * h;
                        var sm = s.match(/_(\\d+)x(\\d+)/);
                        if (sm) { var ua = parseInt(sm[1])*parseInt(sm[2]); if (ua > area) area = ua; }
                        if (area < 40000) return;  // Skip images smaller than ~200x200
                        cdnImgs.push({ url: s, area: area });
                    });
                    cdnImgs.sort(function(a,b){ return b.area - a.area; });
                    for (var i = 0; i < Math.min(cdnImgs.length, 15); i++) {
                        add(cdnImgs[i].url);
                    }

                    // 5. 全页 background-image（CDN 域名）
                    var allStyled = document.querySelectorAll('[style]');
                    for (var i = 0; i < allStyled.length && i < 200; i++) {
                        var bg = allStyled[i].style.backgroundImage || '';
                        var m = bg.match(/url\\(["']?(.*?)["']?\\)/);
                        if (m && m[1] && isCDN(fixURL(m[1]) || '')) add(m[1]);
                    }

                    return urls.slice(0, 9);
                }
            })();
            """
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 每次页面加载完成后重新注入按钮（SPA 跳转可能丢失）
            webView.evaluateJavaScript(Self.floatingButtonJS, completionHandler: nil)
        }

        /// 拦截各种跳出 WebView 的 URL scheme 和重定向
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let s = url.absoluteString.lowercased()
                let scheme = url.scheme?.lowercased() ?? ""
                // Block custom URL schemes that open Taobao/Tmall app
                if scheme == "taobao" || scheme == "tmall" || scheme == "tbopen" ||
                   scheme == "itms-apps" || scheme == "itms-appss" {
                    decisionHandler(.cancel)
                    return
                }
                // Block known app-redirect URLs
                if s.contains("itunes.apple.com") || s.hasPrefix("openapp") ||
                   s.contains("apps.apple.com") {
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "taobaoExtract",
                  let jsonStr = message.body as? String,
                  let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            var info = TaobaoParserService.ProductInfo()
            info.title = dict["title"] as? String
            if let priceStr = dict["price"] as? String {
                info.price = Double(priceStr)
            }

            // 解析图片 URL 数组
            if let urlStrings = dict["imageURLs"] as? [String] {
                info.imageURLs = urlStrings.compactMap { URL(string: $0) }
                info.imageURL = info.imageURLs.first
            }
            // 兼容旧格式 imageURL（单个）
            if info.imageURLs.isEmpty, let imgStr = dict["imageURL"] as? String, let imgURL = URL(string: imgStr) {
                info.imageURL = imgURL
                info.imageURLs = [imgURL]
            }

            info.sourceURL = webView?.url

            // Button is already hidden by JS beginExtract(), take snapshot directly
            if let wv = webView {
                wv.takeSnapshot(with: nil) { [weak self] snapshot, _ in
                    DispatchQueue.main.async {
                        self?.onExtract(info, snapshot)
                    }
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.onExtract(info, nil)
                }
            }
        }
    }
}

// MARK: - Tab 2: 截图识别 (保持不变)

private struct ScreenshotTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allClothingItems: [ClothingItem]
    let preselectedCategory: Category?
    let onDismiss: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var screenshotImage: UIImage?
    @State private var croppedImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var ocrResult: TaobaoParserService.OCRResult?
    @State private var productName = ""
    @State private var productPrice = ""
    @State private var errorMessage: String?
    @State private var step: Step = .selectImage
    @State private var cropRect: CGRect?
    @State private var similarityResult: SimilarityCheckService.CheckResult?
    @State private var savingPhase: SavingPhase = .savingImage
    @State private var showingImageEditor = false

    enum Step {
        case selectImage, analyzing, editInfo, checkingSimilarity, saving
    }

    var body: some View {
        Group {
            switch step {
            case .selectImage:  selectImageView()
            case .analyzing:    analyzingView()
            case .editInfo:     editInfoView()
            case .checkingSimilarity:
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5)
                    Text("正在检查相似衣物...").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .saving:       SavingProgressView(phase: savingPhase)
            }
        }
        .sheet(item: $similarityResult) { result in
            SimilarClothingResultView(
                result: result,
                newImage: processedImage ?? croppedImage,
                onSaveAnyway: {
                    similarityResult = nil
                    saveFromScreenshot(skipSimilarityCheck: true)
                },
                onCancel: {
                    similarityResult = nil
                    step = .editInfo
                }
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showingImageEditor) {
            if let original = croppedImage ?? screenshotImage, let processed = processedImage {
                ImageEditorView(originalImage: original, editingImage: processed) { refined in
                    processedImage = refined
                }
            }
        }
    }

    @ViewBuilder
    private func selectImageView() -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("选择淘宝订单/商品截图")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("系统将自动识别截图中的商品图片\n并提取商品名称和价格")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            PhotosPicker(selection: $selectedPhotoItem, matching: .screenshots) {
                Label("选择截图", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("从相册选择", systemImage: "photo")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            loadAndAnalyze(newItem)
        }
    }

    @ViewBuilder
    private func analyzingView() -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text("正在识别截图内容...").foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func editInfoView() -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if let img = screenshotImage {
                    ZStack {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        if cropRect != nil {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Label("已自动检测商品区域", systemImage: "viewfinder")
                                        .font(.caption2).padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(8)
                        }
                    }
                    .frame(maxHeight: 250)
                }

                if let processed = processedImage ?? croppedImage {
                    VStack(spacing: 4) {
                        Text("提取的商品图").font(.caption).foregroundStyle(.secondary)
                        Image(uiImage: processed)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 180)
                            .background { checkerboard() }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("商品名称").font(.caption).foregroundStyle(.secondary)
                        TextField("输入商品名称", text: $productName).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("价格").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("¥").foregroundStyle(.red)
                            TextField("0.00", text: $productPrice).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        }
                    }
                    if let ocr = ocrResult, !ocr.allTexts.isEmpty {
                        DisclosureGroup("识别到的文字") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(ocr.allTexts.prefix(15).enumerated()), id: \.offset) { _, text in
                                    Text(text).font(.caption2).foregroundStyle(.secondary)
                                        .onTapGesture { productName = text }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 12) {
                    Button { resetState() } label: {
                        Text("重选")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if processedImage != nil {
                        Button { showingImageEditor = true } label: {
                            Text("编辑")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Button { checkScreenshotSimilarity() } label: {
                        Text("保存")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.accentColor).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding()
        }
    }

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

    // MARK: Logic

    private func loadAndAnalyze(_ item: PhotosPickerItem) {
        step = .analyzing
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                await MainActor.run { step = .selectImage }
                return
            }

            let fixed = uiImage.fixedOrientation()
            await MainActor.run { screenshotImage = fixed }

            let parser = TaobaoParserService.shared
            async let ocrTask = parser.recognizeText(from: fixed)
            async let regionTask = parser.detectProductRegion(from: fixed)

            let ocr = try? await ocrTask
            let region = try? await regionTask

            await MainActor.run {
                ocrResult = ocr
                productName = ocr?.productName ?? ""
                if let price = ocr?.price { productPrice = String(format: "%.2f", price) }
            }

            if let region {
                let cropped = parser.cropImage(fixed, to: region)
                await MainActor.run { cropRect = region; croppedImage = cropped }
                if let cropped, let processed = try? await BackgroundRemovalService.shared.removeBackground(from: cropped) {
                    await MainActor.run { processedImage = processed }
                }
            } else {
                if let processed = try? await BackgroundRemovalService.shared.removeBackground(from: fixed) {
                    await MainActor.run { processedImage = processed }
                }
            }

            await MainActor.run { step = .editInfo }
        }
    }

    private func checkScreenshotSimilarity() {
        let imageToCheck = processedImage ?? croppedImage ?? screenshotImage
        guard let imageToCheck else {
            saveFromScreenshot(skipSimilarityCheck: true)
            return
        }

        step = .checkingSimilarity
        Task {
            let result = await SimilarityCheckService.shared.check(
                image: imageToCheck,
                against: allClothingItems,
                newItemCategory: preselectedCategory
            )
            await MainActor.run {
                if result.isEmpty {
                    saveFromScreenshot(skipSimilarityCheck: true)
                } else {
                    similarityResult = result
                }
            }
        }
    }

    private func saveFromScreenshot(skipSimilarityCheck: Bool = false) {
        let imageToSave = processedImage ?? croppedImage ?? screenshotImage
        guard let imageToSave else {
            let item = ClothingItem()
            item.name = productName
            item.purchasePrice = Double(productPrice)
            item.purchaseDate = Date()
            item.category = preselectedCategory
            modelContext.insert(item)
            modelContext.safeSave()
            onDismiss()
            return
        }

        step = .saving
        savingPhase = .savingImage
        Task {
            do {
                let input = ClothingItemFactory.SaveInput(
                    processedImage: imageToSave,
                    originalImage: screenshotImage ?? imageToSave,
                    preselectedCategory: preselectedCategory,
                    name: productName,
                    purchasePrice: Double(productPrice)
                )
                _ = try await ClothingItemFactory.createAndSave(
                    input: input,
                    context: modelContext,
                    onPhaseChange: { savingPhase = $0 }
                )
                onDismiss()
            } catch {
                errorMessage = "保存失败"
                step = .editInfo
            }
        }
    }

    private func resetState() {
        step = .selectImage
        selectedPhotoItem = nil
        screenshotImage = nil
        croppedImage = nil
        processedImage = nil
        ocrResult = nil
        productName = ""
        productPrice = ""
        cropRect = nil
        errorMessage = nil
    }
}
