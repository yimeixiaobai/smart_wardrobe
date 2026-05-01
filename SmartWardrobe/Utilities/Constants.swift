import SwiftUI

enum AppConstants {
    static let appName = "智能衣橱"

    enum Seasons: CaseIterable {
        static let all = ["春", "夏", "秋", "冬"]
    }

    enum Status {
        static let all = ClothingStatus.allCases.map(\.rawValue)
    }

    enum ColorStyle {
        static let all = ["纯色", "条纹", "格子", "印花", "拼接", "渐变"]
    }

    enum Material {
        static let all = ["棉", "涤纶", "丝绸", "羊毛", "亚麻", "牛仔", "皮革", "尼龙", "雪纺", "针织", "羊绒", "其他"]
    }

    enum CollarType {
        static let all = ["圆领", "V领", "翻领", "立领", "方领", "一字领", "高领", "POLO领", "连帽", "无领"]
    }

    enum SleeveLength {
        static let all = ["无袖", "短袖", "五分袖", "七分袖", "长袖"]
    }

    enum ClosureType {
        static let all = ["套头", "拉链", "纽扣", "系带", "魔术贴", "松紧"]
    }

    enum WashingMethod {
        static let all = ["机洗", "手洗", "干洗", "不可水洗"]
    }

    enum PantLength {
        static let all = ["短裤", "五分裤", "七分裤", "九分裤", "长裤"]
    }

    enum SkirtLength {
        static let all = ["超短裙", "膝上裙", "及膝裙", "过膝裙", "及踝裙"]
    }

    enum HeelHeight {
        static let all = ["平底", "低跟", "中跟", "高跟", "超高跟"]
    }

    enum BagSize {
        static let all = ["迷你包", "小号", "中号", "大号", "超大号"]
    }

    enum ShoeClosureType {
        static let all = ["系带", "拉链", "套脚", "魔术贴", "搭扣"]
    }

    enum Occasion {
        static let all = ["日常", "约会", "上班", "运动", "聚会", "旅行", "正式场合"]
    }

    enum CanvasBackground {
        static let styles: [(name: String, color: Color)] = [
            ("淡黄", Color(red: 0.99, green: 0.97, blue: 0.88)),
            ("米白", Color(red: 0.96, green: 0.94, blue: 0.90)),
            ("浅粉", Color(red: 1.0, green: 0.94, blue: 0.95)),
            ("浅蓝", Color(red: 0.93, green: 0.95, blue: 1.0)),
            ("深灰", Color(white: 0.15)),
            ("纯黑", Color.black),
        ]
    }

    enum Mood {
        static let all: [(name: String, emoji: String)] = [
            ("开心", "😊"), ("自信", "😎"), ("舒适", "😌"),
            ("普通", "😐"), ("疲惫", "😴"), ("元气", "🤩")
        ]
    }

    enum API {
        static let qWeatherBaseURL = "https://devapi.qweather.com/v7/weather/now"
        static let qWeatherForecastURL = "https://devapi.qweather.com/v7/weather/3d"
        static let qWeatherGeoURL = "https://geoapi.qweather.com/v2/city/lookup"
        static let weatherCacheDuration: TimeInterval = 30 * 60 // 30 minutes
    }

    enum PresetColors {
        static let all: [(name: String, hex: String)] = [
            // 无彩色系（6 阶）
            ("黑色", "1A1A1A"),
            ("深灰", "404040"),
            ("灰色", "808080"),
            ("浅灰", "B8B8B8"),
            ("米白", "F5F0E8"),
            ("白色", "F8F8F8"),
            // 暖色系
            ("红色", "CC2936"),
            ("酒红", "722F37"),
            ("珊瑚", "E8735A"),
            ("粉色", "E8A0BF"),
            ("橙色", "D4763B"),
            ("杏色", "E8C4A8"),
            ("黄色", "D4A730"),
            ("米色", "D4C5A0"),
            // 冷色系
            ("蓝色", "2F5496"),
            ("浅蓝", "7EB4D2"),
            ("藏蓝", "1E3050"),
            ("青色", "3A8C83"),
            ("绿色", "3A7D5C"),
            ("军绿", "4A5A3A"),
            ("墨绿", "1A3A2A"),
            // 紫色系
            ("紫色", "6B3FA0"),
            ("淡紫", "9B85B4"),
            // 棕色系
            ("棕色", "6B3A2A"),
            ("驼色", "A68B6B"),
            ("卡其", "B8A878"),
        ]
    }
}
