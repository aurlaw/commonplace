import Foundation
import SwiftData

/// Seed content for shell mode and previews, modeled on the design reference.
///
/// Sample data only ever goes into an in-memory container; `seed(into:)` enforces that.
enum SampleData {
    /// The fixed "now" the seed is written around, so "Today" and "Yesterday" read as designed.
    static let now = date(2026, 10, 5, 8, 0)

    /// A new in-memory container holding the seed.
    static func makeContainer() throws -> ModelContainer {
        let container = try ModelContainerFactory.makeInMemory()
        try seed(into: container.mainContext)
        return container
    }

    static func seed(into context: ModelContext) throws {
        precondition(
            context.container.configurations.allSatisfy {
                $0.isStoredInMemoryOnly && $0.cloudKitContainerIdentifier == nil
            },
            "Sample data must never be inserted into the persistent container."
        )
        var seeder = Seeder(context: context)
        seeder.seedStoicPractice()
        seeder.seedSedonaTrip()
        seeder.seedCigars()
        seeder.seedAppIdeas()
        seeder.seedDollySods()
        seeder.seedKitchenRemodel()
        try context.save()
    }

    /// A local-time date, so seeded times read the same in any time zone.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )
        return Calendar.current.date(from: components) ?? .distantPast
    }
}

/// Approximate coordinates for the seed's places; `name` is `nil` for an entry whose place
/// name hasn't been looked up.
private struct Place {
    let latitude: Double
    let longitude: Double
    let name: String?

    init(_ latitude: Double, _ longitude: Double, _ name: String?) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }
}

private struct Seeder {
    let context: ModelContext
    private var nextPhotoSeed = 0

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Topics

    mutating func seedStoicPractice() {
        let topic = addTopic(
            "Stoic practice",
            summary: "Morning intentions and an evening review.",
            color: .indigo,
            createdAt: SampleData.date(2026, 1, 1, 7, 0)
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 10, 5, 6, 42),
            """
            Morning. In my control today: the draft, the run, how I answer Jonah’s email. Not in \
            my control: whether the board likes the plan.

            Premeditatio — the 2:00 will run long and someone will push back. Fine. Answer the \
            question, not the tone.
            """
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 10, 4, 21, 30),
            """
            Evening. Lost patience in the checkout line over a four-minute wait, and noticed it \
            late. Letting it go would have cost nothing.
            """
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 10, 4, 6, 35),
            """
            Morning. Travel day. Delays are likely and none of them are mine to fix. The only \
            job is to be decent company.
            """
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 10, 3, 21, 50),
            "Evening. Did the hard thing first for once. The dread was bigger than the task."
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 29, 6, 40),
            """
            Morning. Packing for the trip. Wanting everything to go well is not the same as \
            needing it to.
            """
        )
    }

    mutating func seedSedonaTrip() {
        let topic = addTopic(
            "Sedona trip",
            summary: """
                Five days in red rock country, Sep 30 – Oct 4. Trail notes, sunrises, and where \
                we ate.
                """,
            color: .orange,
            createdAt: SampleData.date(2026, 9, 24, 19, 0)
        )
        topic.capturesLocation = true
        addEntry(
            to: topic, at: SampleData.date(2026, 10, 4, 5, 58),
            """
            Last sunrise. Airport Mesa overlook was packed by 6:15, so we walked the loop trail \
            instead and had the whole west side to ourselves.
            """,
            photos: 3,
            place: Place(34.8553, -111.7800, "Airport Mesa")
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 10, 3, 19, 24),
            "Elote Cafe. Get the fire-roasted corn. 50-minute wait, worth it.",
            place: Place(34.8623, -111.7629, "Sedona, AZ")
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 10, 3, 8, 50),
            """
            Devil’s Bridge from the Dry Creek Rd lot, about 4 miles round trip. By nine the line \
            for the bridge photo was forty people deep — the view from the far side is better \
            anyway.
            """,
            photos: 5,
            place: Place(34.9027, -111.8138, "Devil’s Bridge Trailhead")
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 10, 2, 6, 10),
            """
            Cathedral Rock at first light. Trailhead lot was already half full at 5:40, mostly \
            headlamps and tripods.

            The trail is short — barely over a mile round trip — but the last third is a \
            hands-and-feet scramble up the chute. Easier going up than coming down. We sat at \
            the saddle for twenty minutes while the sun hit Courthouse Butte first, then the \
            whole valley went orange at once.

            Next time: gloves for the slickrock, and a weekday.
            """,
            photos: 6,
            place: Place(34.8253, -111.7885, "Cathedral Rock Trailhead")
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 10, 1, 15, 15),
            """
            Rest day. Tlaquepaque in the afternoon; bought one small blue tile for the kitchen \
            windowsill.
            """,
            photos: 1,
            // Saved offline: coordinates with no place name yet.
            place: Place(34.8626, -111.7634, nil)
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 30, 16, 40),
            "Arrived. 91° at check-in. Everything is redder than the photos.",
            place: Place(34.8697, -111.7610, "Sedona, AZ")
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 30, 17, 5),
            "Red Rock Pass receipt.",
            photos: 1,
            deletedAt: SampleData.date(2026, 9, 30, 20, 0)
        )
    }

    mutating func seedCigars() {
        let topic = addTopic(
            "Cigars",
            summary: "Tasting notes.",
            color: .brown,
            createdAt: SampleData.date(2026, 3, 14, 20, 0)
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 28, 20, 15),
            """
            Oliva Serie V Melanio. Leather and cedar up front, sweeter in the last third. Needed \
            two touch-ups. 7/10.
            """
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 27, 21, 0),
            "Padrón 1964 Maduro. Cocoa, espresso, pepper on the retrohale. Even burn. 8/10.",
            deletedAt: SampleData.date(2026, 9, 28, 9, 0)
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 20, 19, 40),
            """
            My Father Le Bijou 1922. Pepper for the first inch, then dark chocolate. Slow, even \
            burn. 9/10.
            """
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 6, 18, 30),
            "Arturo Fuente Hemingway Short Story. Forty minutes, no drama. 8/10."
        )
    }

    mutating func seedAppIdeas() {
        let topic = addTopic(
            "App ideas",
            summary: "Rough notes. Most of these should stay notes.",
            color: .purple,
            createdAt: SampleData.date(2026, 2, 9, 12, 0)
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 30, 9, 12),
            "Widget that resurfaces one old entry each morning — “on this day,” but for any topic.",
            deletedAt: SampleData.date(2026, 10, 1, 8, 30)
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 21, 22, 5),
            "Trail log that works with no signal and syncs later."
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 14, 13, 20),
            "Grocery list that sorts itself by the aisle order of the store you’re standing in."
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 3, 7, 55),
            """
            Reading tracker that asks one question when you finish: would you hand this to a \
            friend?
            """
        )
    }

    mutating func seedDollySods() {
        let topic = addTopic(
            "Dolly Sods",
            summary: "Backpacking loop, West Virginia.",
            color: .green,
            createdAt: SampleData.date(2026, 6, 1, 18, 0)
        )
        topic.isArchived = true
        addEntry(
            to: topic, at: SampleData.date(2026, 6, 14, 7, 20),
            "Camped at the Forks of Red Creek. Cold enough for a hat in June.",
            photos: 2,
            place: Place(39.0170, -79.3540, nil)
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 6, 13, 9, 5),
            """
            Bear Rocks trailhead by nine. Fog so thick on the plateau we went cairn to cairn.
            """,
            place: Place(39.0637, -79.3035, "Bear Rocks Trailhead")
        )
    }

    mutating func seedKitchenRemodel() {
        let topic = addTopic(
            "Kitchen remodel",
            summary: "Decisions, dates, and what the contractor said.",
            color: .teal,
            createdAt: SampleData.date(2026, 7, 20, 10, 0)
        )
        topic.deletedAt = SampleData.date(2026, 9, 19, 11, 0)
        addEntry(
            to: topic, at: SampleData.date(2026, 9, 12, 16, 30),
            "Countertop template appointment moved to the 22nd."
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 8, 24, 12, 10),
            "Demo day. The soffit was hiding ductwork nobody mentioned."
        )
        addEntry(
            to: topic, at: SampleData.date(2026, 8, 3, 14, 45),
            "Cabinet order placed. Eight weeks, they say."
        )
    }

    // MARK: Building blocks

    private func addTopic(
        _ title: String,
        summary: String,
        color: TopicColor,
        createdAt: Date
    ) -> Topic {
        let topic = Topic(title: title, summary: summary, color: color, createdAt: createdAt)
        context.insert(topic)
        return topic
    }

    private mutating func addEntry(
        to topic: Topic,
        at date: Date,
        _ body: String,
        photos photoCount: Int = 0,
        place: Place? = nil,
        deletedAt: Date? = nil
    ) {
        let entry = Entry(body: body, date: date, topic: topic, createdAt: date)
        entry.deletedAt = deletedAt
        entry.latitude = place?.latitude
        entry.longitude = place?.longitude
        entry.placeName = place?.name
        context.insert(entry)
        for order in 0..<photoCount {
            let photo = Photo(
                imageData: PlaceholderImage.jpegData(seed: nextPhotoSeed, longEdge: 900),
                thumbnailData: PlaceholderImage.jpegData(seed: nextPhotoSeed, longEdge: 160),
                order: order,
                entry: entry,
                createdAt: date.addingTimeInterval(TimeInterval(order))
            )
            context.insert(photo)
            nextPhotoSeed += 1
        }
    }
}
