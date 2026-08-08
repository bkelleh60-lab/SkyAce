import Foundation

/// Centralized narrative content for the mission intro screens (SKY-61).
///
/// Every user-facing story string — the one-time game intro, the ten
/// per-level mission briefs, and the Clear Skies → Storm Chaser chapter
/// transition — lives here so copy can be updated without touching any scene
/// file. Scenes read from `MissionContent`; they must never hardcode strings.
///
/// Copy is the finalized, approved text from SKY-69 (Captain Rio's voice).

/// The one-time game intro shown on first launch, before the menu / level
/// select. `body` is a short paragraph establishing the world and tone.
struct GameIntro {
    let body: String
}

/// A single per-level mission brief shown on the briefing card before
/// gameplay loads. `tagline` is a short punchy mission name; `storyContext`
/// is one to two sentences of world flavor delivered in Captain Rio's voice.
struct MissionBrief {
    let level: Int
    let tagline: String
    let storyContext: String
    let chapter: Chapter
}

/// The two lines shown on the chapter transition screen between L5 and L6.
struct ChapterTransition {
    /// Celebrates clearing Chapter 1 (Clear Skies) and teases the storm.
    let chapterOneComplete: String
    /// Sets the tone for Chapter 2 (Storm Chaser).
    let chapterTwoIntro: String
}

/// Static store of all mission narrative content. Populated directly from the
/// approved SKY-69 copy.
enum MissionContent {

    // MARK: - Game intro

    static let gameIntro = GameIntro(
        body: "Welcome to Skyview Flight Academy. Captain Rio is your instructor, and she thinks you've got what it takes."
    )

    // MARK: - Chapter transition

    static let chapterTransition = ChapterTransition(
        chapterOneComplete: "You cleared Clear Skies. Somewhere ahead, the wind is already picking up.",
        chapterTwoIntro: "Welcome to Storm Chaser, where the best pilots learn what they're made of."
    )

    // MARK: - Mission briefs

    /// One brief per level, in level order. Chapters follow the catalog split:
    /// levels 1–5 are Clear Skies, levels 6–10 are Storm Chaser.
    static let all: [MissionBrief] = [
        MissionBrief(
            level: 1,
            tagline: "First Wings Up",
            storyContext: "\"Easy does it. Just you, the sky, and a few gates to clear. Let's see how you handle a plane.\"",
            chapter: .clearSkies
        ),
        MissionBrief(
            level: 2,
            tagline: "Coins in the Clouds",
            storyContext: "\"Sun's out, sky's yours. Grab everything you can find.\"",
            chapter: .clearSkies
        ),
        MissionBrief(
            level: 3,
            tagline: "Racing the Clock",
            storyContext: "\"You've got the basics. Now let's see if you've got speed.\"",
            chapter: .clearSkies
        ),
        MissionBrief(
            level: 4,
            tagline: "Trust Your Hands",
            storyContext: "\"Tighter gates this time. I know you can thread them. Show me.\"",
            chapter: .clearSkies
        ),
        MissionBrief(
            level: 5,
            tagline: "Last Light Over Clear Skies",
            storyContext: "\"This is the last stretch before things change. Fly your best. You're almost through.\"",
            chapter: .clearSkies
        ),
        MissionBrief(
            level: 6,
            tagline: "Wind Picks Up",
            storyContext: "\"Storm Chaser starts now. The wind's already talking. Listen to it.\"",
            chapter: .stormChaser
        ),
        MissionBrief(
            level: 7,
            tagline: "Gaps in the Grey",
            storyContext: "\"Visibility's dropping and the gates are tighter. Stay sharp out there.\"",
            chapter: .stormChaser
        ),
        MissionBrief(
            level: 8,
            tagline: "Chasing Coins Blind",
            storyContext: "\"You'll barely see the coins coming. Trust your gut and go.\"",
            chapter: .stormChaser
        ),
        MissionBrief(
            level: 9,
            tagline: "Racing the Storm",
            storyContext: "\"The clock and the storm are both against you now. Beat them both.\"",
            chapter: .stormChaser
        ),
        MissionBrief(
            level: 10,
            tagline: "Prove You're an Ace",
            storyContext: "\"Everything you've learned comes down to this. Fly it like you mean it.\"",
            chapter: .stormChaser
        )
    ]

    /// The brief for a given level number, or nil if the level is out of range.
    static func brief(forLevel level: Int) -> MissionBrief? {
        return all.first { $0.level == level }
    }
}
