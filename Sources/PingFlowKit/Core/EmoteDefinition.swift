import Foundation

/// An emote the emote wheel can hold. Asset names match the id raw value: `angry_kitty.png` and
/// `angry_kitty.ogg` in `Assets/emotes/`.
struct EmoteDefinition: Identifiable, Hashable, Codable, Sendable {
    enum ID: String, Codable, Hashable, CaseIterable, Sendable {
        case angry_kitty
        case bee_happy
        case bee_mad
        case bee_sad
        case call_me
        case cheeky_poro
        case come_again
        case come_at_me
        case despair
        case did_you_just
        case does_not_compute
        case dont_make_me_laugh
        case facepalm
        case gasp
        case gg_heart
        case good_job_buddy
        case haha_hilarious
        case hats_off
        case how_could_you
        case i_will_destroy_you
        case laughing_out_loud
        case magpie_oopsie
        case maybe_next_time
        case nice
        case nice_try
        case not_today
        case oh
        case okay
        case omg_love_it
        case pain
        case poro_ride
        case poro_snax
        case sad_kitten
        case scout_approved
        case snoozy_poro
        case such_foolishness
        case super_approved
        case teamwork
        case think_about_it
        case unimpressed
        case unworthy
        case unworthy_cn
        case wahaha
        case woah_dizzy
    }

    let id: ID
    let name: String
    /// Category for grouping in the settings editor.
    let category: EmoteCategory

    var textureName: String { id.rawValue }
    var soundName: String { id.rawValue }
}

enum EmoteCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case expressions
    case poro
    case reactions
    case gestures
    /// Whatever the user imported. Listed last, because it is the only group that starts empty.
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .expressions: return "Expressions"
        case .poro: return "Poro"
        case .reactions: return "Reactions"
        case .gestures: return "Gestures"
        case .custom: return "Mine"
        }
    }
}

extension EmoteDefinition {
    static let all: [EmoteDefinition] = [
        .init(id: .angry_kitty, name: "Angry Kitty", category: .poro),
        .init(id: .bee_happy, name: "Bee Happy", category: .poro),
        .init(id: .bee_mad, name: "Bee Mad", category: .poro),
        .init(id: .bee_sad, name: "Bee Sad", category: .poro),
        .init(id: .call_me, name: "Call Me", category: .gestures),
        .init(id: .cheeky_poro, name: "Cheeky Poro", category: .poro),
        .init(id: .come_again, name: "Come Again", category: .gestures),
        .init(id: .come_at_me, name: "Come At Me", category: .gestures),
        .init(id: .despair, name: "Despair", category: .expressions),
        .init(id: .did_you_just, name: "Did You Just", category: .expressions),
        .init(id: .does_not_compute, name: "Does Not Compute", category: .expressions),
        .init(id: .dont_make_me_laugh, name: "Don't Make Me Laugh", category: .expressions),
        .init(id: .facepalm, name: "Facepalm", category: .expressions),
        .init(id: .gasp, name: "Gasp", category: .expressions),
        .init(id: .gg_heart, name: "GG Heart", category: .gestures),
        .init(id: .good_job_buddy, name: "Good Job Buddy", category: .gestures),
        .init(id: .haha_hilarious, name: "Haha Hilarious", category: .expressions),
        .init(id: .hats_off, name: "Hats Off", category: .gestures),
        .init(id: .how_could_you, name: "How Could You", category: .expressions),
        .init(id: .i_will_destroy_you, name: "I Will Destroy You", category: .expressions),
        .init(id: .laughing_out_loud, name: "Laughing Out Loud", category: .expressions),
        .init(id: .magpie_oopsie, name: "Magpie Oopsie", category: .poro),
        .init(id: .maybe_next_time, name: "Maybe Next Time", category: .expressions),
        .init(id: .nice, name: "Nice", category: .gestures),
        .init(id: .nice_try, name: "Nice Try", category: .gestures),
        .init(id: .not_today, name: "Not Today", category: .expressions),
        .init(id: .oh, name: "Oh", category: .expressions),
        .init(id: .okay, name: "Okay", category: .gestures),
        .init(id: .omg_love_it, name: "OMG Love It", category: .expressions),
        .init(id: .pain, name: "Pain", category: .expressions),
        .init(id: .poro_ride, name: "Poro Ride", category: .poro),
        .init(id: .poro_snax, name: "Poro Snax", category: .poro),
        .init(id: .sad_kitten, name: "Sad Kitten", category: .poro),
        .init(id: .scout_approved, name: "Scout Approved", category: .gestures),
        .init(id: .snoozy_poro, name: "Snoozy Poro", category: .poro),
        .init(id: .such_foolishness, name: "Such Foolishness", category: .expressions),
        .init(id: .super_approved, name: "Super Approved", category: .gestures),
        .init(id: .teamwork, name: "Teamwork", category: .gestures),
        .init(id: .think_about_it, name: "Think About It", category: .expressions),
        .init(id: .unimpressed, name: "Unimpressed", category: .expressions),
        .init(id: .unworthy, name: "Unworthy", category: .expressions),
        .init(id: .unworthy_cn, name: "Unworthy CN", category: .expressions),
        .init(id: .wahaha, name: "Wahaha", category: .expressions),
        .init(id: .woah_dizzy, name: "Woah Dizzy", category: .expressions),
    ]

    static let allByID: [ID: EmoteDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func definition(for id: ID) -> EmoteDefinition {
        allByID[id] ?? all[0]
    }
}
