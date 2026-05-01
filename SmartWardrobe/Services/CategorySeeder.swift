import Foundation
import SwiftData

struct CategorySeeder {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.isSystem == true })
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0

        if existingCount == 0 {
            // 首次启动：完整插入所有分类
            let categories = defaultCategories()

            for (index, topLevel) in categories.enumerated() {
                let parent = Category(
                    name: topLevel.name,
                    icon: topLevel.icon,
                    sortOrder: index,
                    isSystem: true
                )
                context.insert(parent)

                for (subIndex, sub) in topLevel.children.enumerated() {
                    let child = Category(
                        name: sub.name,
                        icon: sub.icon,
                        sortOrder: subIndex,
                        isSystem: true,
                        parent: parent
                    )
                    context.insert(child)
                }
            }

            try? context.save()
        } else {
            // 已有数据：补种缺失的子分类（如新版本新增的"其他xx"）
            patchMissingSubcategories(context: context)
        }
    }

    /// 检查每个大类下是否缺少 defaultCategories 中定义的子分类，缺则补上
    private static func patchMissingSubcategories(context: ModelContext) {
        let allDescriptor = FetchDescriptor<Category>()
        guard let allCategories = try? context.fetch(allDescriptor) else { return }

        let topCategories = allCategories.filter { $0.isTopLevel && $0.isSystem }
        let defaults = defaultCategories()
        var changed = false

        for defaultTop in defaults {
            guard let existingTop = topCategories.first(where: { $0.name == defaultTop.name }) else { continue }

            let existingChildNames = Set(existingTop.children.map { $0.name })

            for (subIndex, sub) in defaultTop.children.enumerated() {
                if !existingChildNames.contains(sub.name) {
                    let child = Category(
                        name: sub.name,
                        icon: sub.icon,
                        sortOrder: subIndex,
                        isSystem: true,
                        parent: existingTop
                    )
                    context.insert(child)
                    changed = true
                }
            }
        }

        if changed {
            try? context.save()
        }
    }

    private struct CategoryData {
        let name: String
        let icon: String
        let children: [CategoryData]
    }

    private static func defaultCategories() -> [CategoryData] {
        [
            CategoryData(name: "上衣", icon: "tshirt", children: [
                CategoryData(name: "T恤", icon: "tshirt", children: []),
                CategoryData(name: "POLO衫", icon: "tshirt", children: []),
                CategoryData(name: "衬衫", icon: "tshirt", children: []),
                CategoryData(name: "女衫", icon: "tshirt", children: []),
                CategoryData(name: "马甲", icon: "tshirt", children: []),
                CategoryData(name: "毛衣/针织", icon: "tshirt", children: []),
                CategoryData(name: "卫衣", icon: "tshirt", children: []),
                CategoryData(name: "西装", icon: "tshirt", children: []),
                CategoryData(name: "牛仔衣", icon: "tshirt", children: []),
                CategoryData(name: "棒球服", icon: "tshirt", children: []),
                CategoryData(name: "夹克", icon: "tshirt", children: []),
                CategoryData(name: "棉衣/羊羔绒", icon: "tshirt", children: []),
                CategoryData(name: "风衣", icon: "tshirt", children: []),
                CategoryData(name: "大衣", icon: "tshirt", children: []),
                CategoryData(name: "羽绒服", icon: "tshirt", children: []),
                CategoryData(name: "皮衣", icon: "tshirt", children: []),
                CategoryData(name: "皮草", icon: "tshirt", children: []),
                CategoryData(name: "其他上衣", icon: "tshirt", children: []),
            ]),
            CategoryData(name: "裤子", icon: "figure.walk", children: [
                CategoryData(name: "牛仔裤", icon: "figure.walk", children: []),
                CategoryData(name: "休闲裤", icon: "figure.walk", children: []),
                CategoryData(name: "运动裤", icon: "figure.walk", children: []),
                CategoryData(name: "西裤", icon: "figure.walk", children: []),
                CategoryData(name: "短裤", icon: "figure.walk", children: []),
                CategoryData(name: "打底裤", icon: "figure.walk", children: []),
                CategoryData(name: "阔腿裤", icon: "figure.walk", children: []),
                CategoryData(name: "其他裤子", icon: "figure.walk", children: []),
            ]),
            CategoryData(name: "半身裙", icon: "diamond", children: [
                CategoryData(name: "短裙", icon: "diamond", children: []),
                CategoryData(name: "半身长裙", icon: "diamond", children: []),
                CategoryData(name: "百褶裙", icon: "diamond", children: []),
                CategoryData(name: "A字裙", icon: "diamond", children: []),
                CategoryData(name: "包臀裙", icon: "diamond", children: []),
                CategoryData(name: "其他半身裙", icon: "diamond", children: []),
            ]),
            CategoryData(name: "连体装", icon: "figure.stand.dress", children: [
                CategoryData(name: "连衣裙", icon: "figure.stand.dress", children: []),
                CategoryData(name: "连体裤", icon: "figure.stand.dress", children: []),
                CategoryData(name: "套装", icon: "figure.stand.dress", children: []),
                CategoryData(name: "其他连体装", icon: "figure.stand.dress", children: []),
            ]),
            CategoryData(name: "鞋", icon: "shoe", children: [
                CategoryData(name: "运动鞋", icon: "shoe", children: []),
                CategoryData(name: "帆布鞋", icon: "shoe", children: []),
                CategoryData(name: "高跟鞋", icon: "shoe", children: []),
                CategoryData(name: "平底鞋", icon: "shoe", children: []),
                CategoryData(name: "靴子", icon: "shoe", children: []),
                CategoryData(name: "凉鞋/拖鞋", icon: "shoe", children: []),
                CategoryData(name: "乐福鞋", icon: "shoe", children: []),
                CategoryData(name: "其他鞋", icon: "shoe", children: []),
            ]),
            CategoryData(name: "包", icon: "bag", children: [
                CategoryData(name: "双肩包", icon: "bag", children: []),
                CategoryData(name: "手提包", icon: "bag", children: []),
                CategoryData(name: "斜挎包", icon: "bag", children: []),
                CategoryData(name: "钱包", icon: "bag", children: []),
                CategoryData(name: "腰包", icon: "bag", children: []),
                CategoryData(name: "其他包", icon: "bag", children: []),
            ]),
            CategoryData(name: "帽子", icon: "crown", children: [
                CategoryData(name: "棒球帽", icon: "crown", children: []),
                CategoryData(name: "渔夫帽", icon: "crown", children: []),
                CategoryData(name: "针织帽", icon: "crown", children: []),
                CategoryData(name: "贝雷帽", icon: "crown", children: []),
                CategoryData(name: "其他帽子", icon: "crown", children: []),
            ]),
            CategoryData(name: "首饰", icon: "sparkles", children: [
                CategoryData(name: "项链", icon: "sparkles", children: []),
                CategoryData(name: "耳环", icon: "sparkles", children: []),
                CategoryData(name: "手链/手镯", icon: "sparkles", children: []),
                CategoryData(name: "戒指", icon: "sparkles", children: []),
                CategoryData(name: "胸针", icon: "sparkles", children: []),
                CategoryData(name: "其他首饰", icon: "sparkles", children: []),
            ]),
            CategoryData(name: "配饰", icon: "eyeglasses", children: [
                CategoryData(name: "围巾", icon: "eyeglasses", children: []),
                CategoryData(name: "腰带", icon: "eyeglasses", children: []),
                CategoryData(name: "墨镜", icon: "eyeglasses", children: []),
                CategoryData(name: "手套", icon: "eyeglasses", children: []),
                CategoryData(name: "袜子", icon: "eyeglasses", children: []),
                CategoryData(name: "其他配饰", icon: "eyeglasses", children: []),
            ]),
        ]
    }
}
