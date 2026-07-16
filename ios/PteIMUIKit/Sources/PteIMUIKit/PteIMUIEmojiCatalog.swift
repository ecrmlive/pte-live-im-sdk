import Foundation
import PteIMSDK

/**
 Unicode emoji data used by the bundled picker. Emoji6's Chinese and English
 catalogues represent the same Unicode emoji; we therefore persist the Unicode
 sequence and localise only category labels. No language-specific emoji IDs or
 image assets are required.
 */
public enum PteIMUIEmojiCategory: CaseIterable, Hashable, Sendable {
  case smileysAndEmotion, peopleAndBody, animalsAndNature, foodAndDrink
  case travelAndPlaces, activities, objects, symbols, flags

  public func title(language: PteIMLanguage) -> String {
    let zh: String
    let en: String
    switch self {
    case .smileysAndEmotion: (zh, en) = ("笑脸与情感", "Smileys & Emotion")
    case .peopleAndBody: (zh, en) = ("人物与身体", "People & Body")
    case .animalsAndNature: (zh, en) = ("动物与自然", "Animals & Nature")
    case .foodAndDrink: (zh, en) = ("食物与饮品", "Food & Drink")
    case .travelAndPlaces: (zh, en) = ("旅行与地点", "Travel & Places")
    case .activities: (zh, en) = ("活动", "Activities")
    case .objects: (zh, en) = ("物品", "Objects")
    case .symbols: (zh, en) = ("符号", "Symbols")
    case .flags: (zh, en) = ("旗帜", "Flags")
    }
    return PteIMUILocalization.value(zh, en, language: language)
  }
}

public struct PteIMUIEmojiItem: Hashable, Sendable {
  /** Stable, language-independent message ID: the actual Unicode sequence. */
  public let id: String
  public let category: PteIMUIEmojiCategory
  public init(id: String, category: PteIMUIEmojiCategory) { self.id = id; self.category = category }
}

public enum PteIMUIEmojiCatalog {
  public static func items(in category: PteIMUIEmojiCategory) -> [PteIMUIEmojiItem] {
    let scalars: [String]
    switch category {
    case .smileysAndEmotion: scalars = emoji(in: [0x1F600...0x1F64F, 0x1F900...0x1F9FF])
    case .peopleAndBody: scalars = emoji(in: [0x1F466...0x1F487, 0x1F575...0x1F5FF, 0x1FAC0...0x1FAFF])
    case .animalsAndNature: scalars = emoji(in: [0x1F400...0x1F43E, 0x1F980...0x1F9A2, 0x1F300...0x1F33F])
    case .foodAndDrink: scalars = emoji(in: [0x1F345...0x1F37F, 0x1F950...0x1F96B])
    case .travelAndPlaces: scalars = emoji(in: [0x1F680...0x1F6FF, 0x1F3D4...0x1F3F0])
    case .activities: scalars = emoji(in: [0x1F380...0x1F3CF, 0x1F947...0x1F94C])
    case .objects: scalars = emoji(in: [0x1F4A0...0x1F4FF, 0x1F507...0x1F567])
    case .symbols: scalars = emoji(in: [0x2000...0x2BFF, 0x1F000...0x1F02F, 0x1F0A0...0x1F0FF])
    case .flags: scalars = flags()
    }
    return scalars.map { PteIMUIEmojiItem(id: $0, category: category) }
  }

  public static func allItems() -> [PteIMUIEmojiItem] { PteIMUIEmojiCategory.allCases.flatMap(items) }

  private static func emoji(in ranges: [ClosedRange<UInt32>]) -> [String] {
    ranges.flatMap { range in
      range.compactMap { UnicodeScalar($0) }
        .filter { $0.properties.isEmojiPresentation }
        .map(String.init)
    }
  }

  private static func flags() -> [String] {
    let letters = (0x1F1E6...0x1F1FF).compactMap(UnicodeScalar.init).map(String.init)
    return letters.flatMap { first in letters.map { first + $0 } }
  }
}
