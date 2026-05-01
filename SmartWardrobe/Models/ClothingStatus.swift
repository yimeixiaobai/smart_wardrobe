import Foundation

enum ClothingStatus: String, CaseIterable, Codable {
    case active = "正常"
    case lentOut = "已借出"
    case retired = "已淘汰"
}
