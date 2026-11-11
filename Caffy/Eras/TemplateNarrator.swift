import Foundation

/// The words on an era's card.
nonisolated struct EraContent: Hashable, Sendable {
    let title: String
    /// One line on the era's music.
    let summary: String
    /// The short handwritten label, such as "2026" or "Mar 2026".
    let whenLabel: String
}

/// Writes an era's title, summary and when-label from its facts.
///
/// `TemplateNarrator` does this with fixed templates now. An on-device
/// language model can implement this later, with the templates as fallback.
nonisolated protocol EraNarrator: Sendable {
    func content(for facts: EraFacts) async -> EraContent
}

/// Writes era titles from templates: deterministic, testable and free.
///
/// Where several wordings fit, the era's id picks one with `StableHash`, so
/// the same era always reads the same.
///
/// The templates are English only for now. Month names are spelled out here
/// rather than taken from the device's locale, so titles never mix languages.
nonisolated struct TemplateNarrator: EraNarrator {
    let calendar: Calendar
    /// The current time, for the when-label of an era that's still going.
    let now: Date
    var config: EraBuildConfig = .standard

    func content(for facts: EraFacts) -> EraContent {
        EraContent(title: title(for: facts), summary: summary(for: facts), whenLabel: whenLabel(for: facts))
    }

    // MARK: - Titles

    func title(for facts: EraFacts) -> String {
        switch facts.kind {
        case .trip: tripTitle(for: facts)
        case .home: homeTitle(for: facts)
        }
    }

    private func tripTitle(for facts: EraFacts) -> String {
        let places = facts.placeNames
        switch places.count {
        case 0: return "\(duration(of: facts)) away"
        case 1: return "\(duration(of: facts)) in \(places[0])"
        case 2: return "\(places[0]) & \(places[1])"
        case 3: return "\(places[0]), \(places[1]) & \(places[2])"
        default: return "\(places[0]), \(places[1]) & more"
        }
    }

    private func homeTitle(for facts: EraFacts) -> String {
        let place = facts.placeNames.first

        if !facts.isCurrent, calendar.isDate(facts.start, inSameDayAs: facts.lastPhoto) {
            return "One day in \(Self.monthNames[calendar.component(.month, from: facts.start) - 1])"
        }
        if let place, let change = facts.homeChange {
            switch change {
            case .newHome: return "New in \(place)"
            case .backHome: return "Back in \(place)"
            }
        }
        if let artist = dominantArtist(in: facts.listening) {
            return "On repeat: \(artist)"
        }

        let middle = facts.start.addingTimeInterval(facts.lastPhoto.timeIntervalSince(facts.start) / 2)
        let season = season(of: middle, latitude: facts.latitude)
        let year = calendar.component(.year, from: middle)
        var choices = ["\(season) at home", "\(season), \(year)"]
        if let place {
            choices.append("\(season) in \(place)")
        }
        return choices[StableHash.index(for: facts.id, count: choices.count)]
    }

    /// The artist with at least `dominantArtistShare` of a stretch's plays,
    /// when there's enough listening to say.
    private func dominantArtist(in listening: ListeningProfile) -> String? {
        guard listening.playCount >= config.musicMinPlays, let top = listening.topArtists(1).first else { return nil }
        return Double(top.plays) / Double(listening.playCount) >= config.dominantArtistShare ? top.artist : nil
    }

    // MARK: - Trip length

    /// How many nights a trip lasted: the number of times it passed the
    /// overnight cutoff hour (04:00).
    func nights(of facts: EraFacts) -> Int {
        let shift = TimeInterval(config.overnightCutoffHour * 60 * 60)
        let first = calendar.startOfDay(for: facts.start.addingTimeInterval(-shift))
        let last = calendar.startOfDay(for: facts.lastPhoto.addingTimeInterval(-shift))
        return max(0, calendar.dateComponents([.day], from: first, to: last).day ?? 0)
    }

    /// "A night", "A weekend", "Three days", "A week", "Three weeks"…
    private func duration(of facts: EraFacts) -> String {
        let nights = nights(of: facts)
        let days = nights + 1
        switch nights {
        case ...0: return "A day"
        case 1: return "A night"
        case 2...3 where includesSaturdayNight(facts, nights: nights): return "A weekend"
        case 2...6, 9...12: return "\(Self.spelled(days).capitalizedFirst) days"
        case 7...8: return "A week"
        case 13...17: return "Two weeks"
        case 18...24: return "Three weeks"
        default: return "\(Self.spelled(Int((Double(days) / 7).rounded())).capitalizedFirst) weeks"
        }
    }

    private func includesSaturdayNight(_ facts: EraFacts, nights: Int) -> Bool {
        let shift = TimeInterval(config.overnightCutoffHour * 60 * 60)
        let firstEvening = calendar.startOfDay(for: facts.start.addingTimeInterval(-shift))
        return (0..<nights).contains { night in
            let evening = calendar.date(byAdding: .day, value: night, to: firstEvening)!
            // In the Gregorian calendar, weekday 7 is Saturday.
            return calendar.component(.weekday, from: evening) == 7
        }
    }

    // MARK: - Seasons

    /// The season `date` falls in, by meteorological season (three whole
    /// months each), flipped south of the equator. Northern when unknown.
    private func season(of date: Date, latitude: Double?) -> String {
        let month = calendar.component(.month, from: date)
        let northern = ["Winter", "Spring", "Summer", "Autumn"]
        // December, January and February are season 0.
        let index = (month % 12) / 3
        let isSouthern = (latitude ?? 0) < 0
        return northern[isSouthern ? (index + 2) % 4 : index]
    }

    // MARK: - Summaries

    func summary(for facts: EraFacts) -> String {
        let listening = facts.listening
        guard listening.playCount >= config.musicMinPlays else {
            return facts.kind == .trip ? "No music on this one." : "A quiet one for music."
        }
        let artists = listening.topArtists(2).map(\.artist)

        if facts.kind == .trip {
            return artists.count == 1
                ? "The soundtrack: \(artists[0])."
                : "The soundtrack: \(artists[0]) and \(artists[1])."
        }
        if let shift = genreShift(from: facts.previousListening, to: listening) {
            return shift
        }
        if let top = listening.topArtists(1).first, Double(top.plays) / Double(listening.playCount) >= 0.5 {
            return "Hardly anything but \(top.artist)."
        }
        // The top artist has under half the plays, so there's a second one.
        return "Mostly \(artists[0]) and \(artists[1])."
    }

    /// One line on how the genres changed since the previous era, such as
    /// "Chillout takes over, and Drum & bass arrives.", or `nil` when they
    /// didn't change much or there's too little to compare.
    private func genreShift(from previous: ListeningProfile?, to current: ListeningProfile) -> String? {
        guard let previous, previous.playCount >= config.musicMinPlays else { return nil }
        let before = Self.genreShares(previous)
        let now = Self.genreShares(current)
        guard let topBefore = before.first?.genre, let topNow = now.first?.genre else { return nil }

        let shareBefore = Dictionary(uniqueKeysWithValues: before.map { ($0.genre, $0.share) })
        let arrival = now.first { $0.genre != topNow && $0.share >= 0.2 && (shareBefore[$0.genre] ?? 0) < 0.05 }?.genre

        switch (topNow != topBefore, arrival) {
        case (true, let arrival?): return "\(topNow.capitalizedFirst) takes over, and \(arrival) arrives."
        case (true, nil): return "\(topNow.capitalizedFirst) takes over from \(topBefore)."
        case (false, let arrival?): return "\(arrival.capitalizedFirst) arrives alongside \(topNow)."
        case (false, nil): return nil
        }
    }

    /// Each genre's share of the plays that have one, biggest first, then by name.
    private static func genreShares(_ listening: ListeningProfile) -> [(genre: String, share: Double)] {
        let total = listening.genrePlays.values.reduce(0, +)
        guard total > 0 else { return [] }
        return listening.genrePlays
            .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .map { (genre: $0.key, share: Double($0.value) / Double(total)) }
    }

    // MARK: - When-labels

    /// "2026" for an era within one year, "2025–26" across years, and
    /// "Mar 2026" for a trip.
    func whenLabel(for facts: EraFacts) -> String {
        let startYear = calendar.component(.year, from: facts.start)
        if facts.kind == .trip {
            return "\(Self.shortMonthNames[calendar.component(.month, from: facts.start) - 1]) \(startYear)"
        }
        let endYear = calendar.component(.year, from: facts.end ?? max(now, facts.lastPhoto))
        guard endYear > startYear else { return "\(startYear)" }
        return "\(startYear)–\(String(format: "%02d", endYear % 100))"
    }

    // MARK: - Words

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    static let shortMonthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static let numberWords = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"
    ]

    /// "three" for 3. Numbers above twenty stay as digits.
    static func spelled(_ number: Int) -> String {
        numberWords.indices.contains(number) ? numberWords[number] : "\(number)"
    }
}

private extension String {
    /// The string with its first letter in upper case, the rest untouched.
    nonisolated var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
