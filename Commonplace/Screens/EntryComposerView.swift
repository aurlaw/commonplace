import PhotosUI
import SwiftData
import SwiftUI

/// How the composer was opened. Decides the title and where the topic appears.
enum ComposerMode: Identifiable {
    /// From the Topics list: the topic chip is a menu.
    case newFromList
    /// From inside a topic: the topic moves into the subtitle.
    case newInTopic(Topic)
    case edit(Entry)

    var id: String {
        switch self {
        case .newFromList: "new-from-list"
        case .newInTopic: "new-in-topic"
        case .edit: "edit"
        }
    }
}

/// A photo in the composer. Newly picked photos stay values until Save, so Cancel or a failed
/// save can't leave orphaned `Photo` records.
enum DraftPhoto: Identifiable {
    /// Already saved on the entry.
    case existing(Photo)
    /// Picked and processed, not yet inserted.
    case new(id: UUID, image: Data, thumbnail: Data)

    enum ID: Hashable {
        case existing(PersistentIdentifier)
        case new(UUID)
    }

    var id: ID {
        switch self {
        case .existing(let photo): .existing(photo.persistentModelID)
        case .new(let id, _, _): .new(id)
        }
    }

    var thumbnailData: Data? {
        switch self {
        case .existing(let photo): photo.thumbnailData
        case .new(_, _, let thumbnail): thumbnail
        }
    }
}

/// The composer's working copy, written to the store only on Save.
struct EntryDraft {
    var topic: Topic?
    var date: Date
    var body = ""
    /// In display order. Add with `addPhoto(_:)`, which enforces the per-entry limit.
    var photos: [DraftPhoto] = []
    var dictation = Dictation.idle
    /// Whether this entry should carry a location. Starts from the topic's setting for a new
    /// entry and from whether the entry has one for an edit. Change it with
    /// `setCapturesLocation(_:)`.
    private(set) var capturesLocation = false
    /// Where the location stands. Change it through the `capture…` methods.
    private(set) var location = LocationState.none
    /// Whether the location choice was made by hand in this sheet, after which changing the
    /// topic no longer changes it.
    private(set) var hasToggledLocation = false
    let isEditing: Bool
    /// The location the entry was saved with, restored if a replacement can't be captured.
    private let savedLocation: LocationState

    enum LocationState: Equatable {
        /// Nothing captured (yet).
        case none
        case locating
        /// Captured in this sheet. The place name arrives after the coordinate, or not at all.
        case captured(Coordinate, placeName: String?)
        /// The edited entry's saved location, unchanged.
        case existing(Coordinate, placeName: String?)
        /// Location access is off for the app.
        case denied
        case failed
    }

    enum Dictation: Equatable {
        case idle
        /// `pending` is the unconfirmed tail of the transcript, shown grey.
        case listening(pending: String, elapsedSeconds: Int)

        /// The design's dictation-active frame.
        static let sample = Dictation.listening(
            pending: "and the wind at the saddle was strong enough to",
            elapsedSeconds: 14
        )
    }

    init(mode: ComposerMode, now: Date) {
        switch mode {
        case .newFromList:
            date = now
            isEditing = false
            savedLocation = .none
        case .newInTopic(let topic):
            self.topic = topic
            date = now
            isEditing = false
            savedLocation = .none
            capturesLocation = topic.capturesLocation
        case .edit(let entry):
            topic = entry.topic
            date = entry.date
            body = entry.body
            photos = entry.sortedPhotos.map(DraftPhoto.existing)
            isEditing = true
            if entry.hasLocation, let latitude = entry.latitude, let longitude = entry.longitude {
                let coordinate = Coordinate(latitude: latitude, longitude: longitude)
                savedLocation = .existing(coordinate, placeName: entry.placeName)
                capturesLocation = true
            } else {
                savedLocation = .none
            }
            location = savedLocation
        }
    }

    /// The body as it would be stored: no surrounding whitespace or newlines; inner line
    /// breaks kept.
    var trimmedBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An entry needs a topic, and text or at least one photo.
    var isValid: Bool {
        topic != nil && (!trimmedBody.isEmpty || !photos.isEmpty)
    }

    /// How many more photos this entry can take.
    var remainingPhotoSlots: Int {
        max(0, PhotoLimits.maxPhotosPerEntry - photos.count)
    }

    /// Appends a processed photo, unless the entry is already at the limit.
    ///
    /// - Returns: Whether the photo was added.
    @discardableResult
    mutating func addPhoto(_ processed: ProcessedImage) -> Bool {
        guard remainingPhotoSlots > 0 else {
            return false
        }
        photos.append(.new(id: UUID(), image: processed.image, thumbnail: processed.thumbnail))
        return true
    }

    mutating func removePhoto(_ id: DraftPhoto.ID) {
        photos.removeAll { $0.id == id }
    }

    /// Whether saving would store something different from `original`.
    ///
    /// Compares the trimmed body, the date, the topic, which photos are present (added or
    /// removed), and the location choice. Dictation state never makes a draft dirty, and nor
    /// does a location captured automatically for a new entry.
    func isDirty(comparedTo original: EntryDraft) -> Bool {
        trimmedBody != original.trimmedBody || date != original.date || topic !== original.topic
            || photos.map(\.id) != original.photos.map(\.id)
            || capturesLocation != original.capturesLocation
            || (isEditing && hasNewLocation)
    }

    // MARK: Location

    /// Whether a capture should be started: location is wanted and there is none.
    var needsCapture: Bool {
        capturesLocation && location == .none
    }

    var isLocating: Bool {
        location == .locating
    }

    /// Whether a location was captured in this sheet.
    private var hasNewLocation: Bool {
        if case .captured = location { true } else { false }
    }

    /// Changes the topic. The location choice follows the new topic's setting, unless it has
    /// already been made by hand in this sheet.
    mutating func setTopic(_ newTopic: Topic?) {
        topic = newTopic
        guard !isEditing, !hasToggledLocation else {
            return
        }
        capturesLocation = newTopic?.capturesLocation ?? false
        if !capturesLocation {
            location = .none
        }
    }

    /// The user's own choice to include or remove the location.
    mutating func setCapturesLocation(_ isOn: Bool) {
        hasToggledLocation = true
        capturesLocation = isOn
        if !isOn {
            location = .none
        } else if location == .denied || location == .failed {
            // Turning it back on is a fresh attempt.
            location = .none
        }
    }

    /// Asks for a fresh fix: "Use Current Location" on an edit, or another try after a failure.
    /// An edited entry's saved location is replaced only if the new fix arrives.
    mutating func requestCurrentLocation() {
        hasToggledLocation = true
        capturesLocation = true
        location = .none
    }

    mutating func captureStarted() {
        if needsCapture {
            location = .locating
        }
    }

    /// Records a fix, if one is still being waited for.
    mutating func captureSucceeded(_ coordinate: Coordinate) {
        if isLocating {
            location = .captured(coordinate, placeName: nil)
        }
    }

    /// Adds the place name to the captured fix it belongs to.
    mutating func captureNamed(_ coordinate: Coordinate, placeName: String) {
        if location == .captured(coordinate, placeName: nil) {
            location = .captured(coordinate, placeName: placeName)
        }
    }

    /// Records a failed capture. An edited entry falls back to the location it already had.
    mutating func captureFailed(_ error: LocationError) {
        guard isLocating else {
            return
        }
        if case .existing = savedLocation {
            location = savedLocation
        } else {
            location = error == .denied ? .denied : .failed
        }
    }

    /// The chip's text for the current state.
    var locationLabel: String {
        guard capturesLocation else {
            return "No Location"
        }
        switch location {
        case .none, .locating:
            return "Locating…"
        case .captured(_, let placeName):
            return placeName ?? "Current Location"
        case .existing(let coordinate, let placeName):
            return LocationLabel.text(
                placeName: placeName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        case .denied:
            return "Location Off"
        case .failed:
            return "Location Unavailable"
        }
    }

    /// Writes the location choice to an entry. Call before saving.
    ///
    /// - Location turned off: clears coordinates and place name together.
    /// - Captured in this sheet: sets coordinates, and the place name if it is already known.
    /// - Anything else (unchanged, still locating, denied, failed): leaves the entry alone, so
    ///   an edit never loses a location it didn't deliberately replace.
    func applyLocation(to entry: Entry) {
        guard capturesLocation else {
            if entry.latitude != nil || entry.longitude != nil || entry.placeName != nil {
                entry.latitude = nil
                entry.longitude = nil
                entry.placeName = nil
            }
            return
        }
        if case .captured(let coordinate, let placeName) = location {
            entry.latitude = coordinate.latitude
            entry.longitude = coordinate.longitude
            entry.placeName = placeName
        }
    }

    /// A new, uninserted entry with the topic, date, and trimmed body.
    func makeEntry() -> Entry {
        Entry(body: trimmedBody, date: date, topic: topic)
    }

    /// Writes the date and trimmed body to an existing entry, and nothing else (not photos, not
    /// location).
    func apply(to entry: Entry) {
        entry.date = date
        entry.body = trimmedBody
    }

    /// Makes the entry's photos match the draft. Call before saving, for new and edited
    /// entries alike.
    ///
    /// - Existing photos no longer in the draft are **hard deleted**: removing a photo is the
    ///   one user-facing delete that skips Trash.
    /// - New photos are inserted.
    /// - `order` is rewritten 0…n-1 to match the draft.
    ///
    /// Touches nothing else on the entry.
    func applyPhotos(to entry: Entry, in context: ModelContext) {
        let kept = Set(photos.map(\.id))
        for photo in entry.photos ?? [] where !kept.contains(.existing(photo.persistentModelID)) {
            context.delete(photo)
        }
        for (order, draftPhoto) in photos.enumerated() {
            switch draftPhoto {
            case .existing(let photo):
                if photo.order != order {
                    photo.order = order
                }
            case .new(_, let image, let thumbnail):
                context.insert(
                    Photo(imageData: image, thumbnailData: thumbnail, order: order, entry: entry)
                )
            }
        }
    }
}

extension EnvironmentValues {
    /// Downscales and thumbnails picked photos. Replaced with a fake in tests.
    @Entry var imageProcessor: any ImageProcessor = ImageIOProcessor()
}

/// One trip to the photo library: the items picked, processed in pick order.
private struct PhotoBatch {
    let id = UUID()
    let items: [PhotosPickerItem]
}

/// New / Edit Entry sheet. Save inserts a new entry or writes back to the edited one.
struct EntryComposerView: View {
    let mode: ComposerMode
    let now: Date

    @Query(filter: #Predicate<Topic> { $0.deletedAt == nil && !$0.isArchived })
    private var topics: [Topic]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.imageProcessor) private var imageProcessor
    @Environment(\.locationService) private var locationService
    @Environment(\.locationCapture) private var locationCapture
    @Environment(\.openURL) private var openURL
    /// A per-device preference, not synced. See `LastUsedTopic`.
    @AppStorage(LastUsedTopic.storageKey) private var lastUsedTopic: Data?
    @State private var draft: EntryDraft
    /// What the sheet opened with, for detecting unsaved changes.
    @State private var original: EntryDraft
    @State private var isPickingDate = false
    @State private var isConfirmingDiscard = false
    @State private var saveError: String?
    @State private var pickerSelection: [PhotosPickerItem] = []
    /// The batch being processed. Tied to the sheet, so dismissing it cancels the work.
    @State private var photoBatch: PhotoBatch?
    /// Picked photos not yet processed; each shows a placeholder tile.
    @State private var pendingPhotoCount = 0
    @State private var photoMessage: String?
    /// The location request in flight. Tied to the sheet, so dismissing it cancels the request.
    @State private var captureID: UUID?
    @State private var captureStartedAt: ContinuousClock.Instant?
    @FocusState private var isBodyFocused: Bool

    /// - Parameter draft: Overrides the draft derived from `mode`; previews use it to show a
    ///   specific state.
    init(mode: ComposerMode, now: Date, draft: EntryDraft? = nil) {
        self.mode = mode
        self.now = now
        _draft = State(initialValue: draft ?? EntryDraft(mode: mode, now: now))
        _original = State(initialValue: EntryDraft(mode: mode, now: now))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                chipRow
                textArea
                photoRow
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(TopicSubtitle(topic: subtitleTopic))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            isConfirmingDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog(
                        "Discard changes?",
                        isPresented: $isConfirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button("Discard Changes", role: .destructive) {
                            dismiss()
                        }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!draft.isValid || isProcessingPhotos)
                }
            }
        }
        // With unsaved changes, swipe-down is blocked so Cancel's confirmation is the way out.
        .interactiveDismissDisabled(isDirty || isProcessingPhotos)
        .saveErrorAlert($saveError)
        .onChange(of: pickerSelection) { _, items in
            guard !items.isEmpty else {
                return
            }
            // Cleared so the next trip to the library starts fresh.
            pickerSelection = []
            pendingPhotoCount = items.count
            photoMessage = nil
            photoBatch = PhotoBatch(items: items)
        }
        .task(id: photoBatch?.id) {
            await processPhotoBatch()
        }
        .task(id: captureID) {
            await captureLocation()
        }
        .onAppear {
            if isFromList, draft.topic == nil {
                // The default topic is where the sheet starts, not a change to it.
                let topic = LastUsedTopic.resolve(stored: lastUsedTopic, among: topics)
                draft.setTopic(topic)
                original.setTopic(topic)
            }
            isBodyFocused = draft.dictation == .idle
            // Location is captured when the composer opens, not on Save.
            syncLocationCapture()
        }
    }

    // MARK: Location

    /// Starts a capture when the draft wants one, and stops one it no longer wants. Call after
    /// anything that changes the draft's location choice.
    private func syncLocationCapture() {
        if draft.needsCapture {
            draft.captureStarted()
            captureStartedAt = .now
            captureID = UUID()
        } else if !draft.capturesLocation {
            captureID = nil
        }
    }

    /// One fix, then its place name if the device is online. This is where the system asks for
    /// location access, the first time a composer opens with location on.
    private func captureLocation() async {
        guard captureID != nil else {
            return
        }
        do {
            let coordinate = try await locationService.currentLocation(
                timeout: LocationCaptureRule.timeout
            )
            draft.captureSucceeded(coordinate)
            if let name = try? await locationService.placeName(for: coordinate) {
                draft.captureNamed(coordinate, placeName: name)
            }
        } catch let error as LocationError {
            draft.captureFailed(error)
        } catch {
            // Cancelled: the sheet closed or the location was turned off.
        }
    }

    /// After a save, hands unfinished location work to the app so it outlives the sheet: a fix
    /// still being waited for, or a place name not yet looked up.
    private func handOffLocation(for entry: Entry) {
        guard let locationCapture else {
            return
        }
        if draft.isLocating, let captureStartedAt {
            let remaining = LocationCaptureRule.timeout - (ContinuousClock.now - captureStartedAt)
            if remaining > .zero {
                locationCapture.startLateFix(for: entry.persistentModelID, timeout: remaining)
            }
        } else if LocationCapture.needsPlaceName(entry) {
            locationCapture.startFillingPlaceName(for: entry.persistentModelID)
        }
    }

    private var isDirty: Bool {
        draft.isDirty(comparedTo: original)
    }

    private var isProcessingPhotos: Bool {
        pendingPhotoCount > 0
    }

    /// Loads and processes the picked photos one at a time, in pick order, so tiles fill in
    /// left to right and only one full-size image is in memory at once. A photo that can't be
    /// loaded or decoded is dropped; the rest still succeed.
    private func processPhotoBatch() async {
        guard let batch = photoBatch else {
            return
        }
        var failures = 0
        for item in batch.items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ImageProcessingError.undecodable
                }
                let processed = try await imageProcessor.process(data)
                // The sheet was dismissed: discard the result.
                try Task.checkCancellation()
                if !draft.addPhoto(processed) {
                    failures += 1
                }
            } catch is CancellationError {
                return
            } catch {
                failures += 1
            }
            pendingPhotoCount -= 1
        }
        pendingPhotoCount = 0
        if failures > 0 {
            let message =
                failures == 1
                ? "1 photo couldn’t be added" : "\(failures) photos couldn’t be added"
            photoMessage = message
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// Dismisses on success. On failure the sheet stays open with the draft intact.
    private func save() {
        let entry: Entry
        if case .edit(let edited) = mode {
            entry = edited
            draft.apply(to: entry)
        } else {
            entry = draft.makeEntry()
            modelContext.insert(entry)
        }
        draft.applyPhotos(to: entry, in: modelContext)
        draft.applyLocation(to: entry)
        // Saving doesn't wait for a fix: one that arrives later is attached to the saved entry.
        saveError = modelContext.saveOrRollback()
        guard saveError == nil else {
            return
        }
        handOffLocation(for: entry)
        if !isEditing, let topic = draft.topic {
            // Only new entries move the last-used topic; edits don't.
            lastUsedTopic = LastUsedTopic.encode(topic)
        }
        dismiss()
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var isFromList: Bool {
        if case .newFromList = mode { true } else { false }
    }

    private var title: String {
        isEditing ? "Edit Entry" : "New Entry"
    }

    /// The topic shown under the title; `nil` when the chip row carries the topic instead.
    private var subtitleTopic: Topic? {
        isFromList ? nil : draft.topic
    }

    // MARK: Chips

    /// One row when the chips fit. When they don't (three chips from the topics list), the
    /// location chip drops to its own row so nothing is pushed off screen.
    private var chipRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                topicChip
                dateChip
                locationChip
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    topicChip
                    dateChip
                }
                locationChip
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// The topic picker's selection, routed through the draft so the location choice follows
    /// the topic.
    private var topicSelection: Binding<Topic?> {
        Binding(
            get: { draft.topic },
            set: { topic in
                draft.setTopic(topic)
                syncLocationCapture()
            }
        )
    }

    /// Only when opened from the topics list; otherwise the topic is in the subtitle.
    @ViewBuilder private var topicChip: some View {
        if isFromList {
            Menu {
                Picker("Topic", selection: topicSelection) {
                    ForEach(Topic.sortedByRecentActivity(topics)) { topic in
                        Text(topic.title).tag(Optional(topic))
                    }
                }
            } label: {
                ComposerChip {
                    TopicChip(topic: draft.topic, dotSize: 9)
                }
            }
            .accessibilityLabel("Topic")
            .accessibilityValue(draft.topic?.title ?? "None")
        }
    }

    private var dateChip: some View {
        Button {
            isPickingDate = true
        } label: {
            ComposerChip {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text(EntryTimeline.composerDate(draft.date, now: now))
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("Date")
        .accessibilityValue(EntryTimeline.composerDate(draft.date, now: now))
        .popover(isPresented: $isPickingDate) {
            // Back-dating is fine; future dates are not.
            DatePicker("Date", selection: $draft.date, in: ...now)
                .datePickerStyle(.graphical)
                .padding()
                .frame(minWidth: 320)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var locationChip: some View {
        Menu {
            if draft.capturesLocation {
                if draft.isEditing, !draft.isLocating {
                    Button("Use Current Location", systemImage: "location") {
                        draft.requestCurrentLocation()
                        syncLocationCapture()
                    }
                } else if draft.location == .failed {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        draft.requestCurrentLocation()
                        syncLocationCapture()
                    }
                }
                if draft.location == .denied,
                    let url = URL(string: UIApplication.openSettingsURLString)
                {
                    Button("Open Settings", systemImage: "gear") {
                        openURL(url)
                    }
                }
                Button("Remove Location", systemImage: "location.slash") {
                    draft.setCapturesLocation(false)
                    syncLocationCapture()
                }
            } else {
                Button(
                    draft.isEditing ? "Use Current Location" : "Include Location",
                    systemImage: "location"
                ) {
                    draft.setCapturesLocation(true)
                    syncLocationCapture()
                }
            }
        } label: {
            ComposerChip {
                locationChipIcon
                Text(draft.locationLabel)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("Location")
        .accessibilityValue(draft.locationLabel)
    }

    @ViewBuilder private var locationChipIcon: some View {
        if !draft.capturesLocation {
            Image(systemName: "location.slash")
                .foregroundStyle(.secondary)
        } else {
            switch draft.location {
            case .none, .locating:
                ProgressView()
                    .controlSize(.mini)
            case .captured, .existing:
                Image(systemName: "location.fill")
                    .foregroundStyle(.secondary)
            case .denied, .failed:
                Image(systemName: "location.slash")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Text + dictation

    private var textArea: some View {
        ZStack(alignment: .bottomTrailing) {
            if case .listening(let pending, _) = draft.dictation {
                // While listening, the confirmed text is followed by the grey unconfirmed tail.
                ScrollView {
                    Text("\(draft.body)\(Text(pending).foregroundStyle(.secondary))")
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }
            } else {
                TextEditor(text: $draft.body)
                    .focused($isBodyFocused)
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 15)
                    .padding(.top, 6)
                    .accessibilityLabel("Entry text")
            }
            dictationControl
                .padding(.trailing, 16)
                .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity)
    }

    /// Toggles the visual state only: no audio is recorded in the shell.
    @ViewBuilder private var dictationControl: some View {
        if case .listening(_, let elapsedSeconds) = draft.dictation {
            Button {
                draft.dictation = .idle
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                    LevelMeter()
                    Text(Duration.seconds(elapsedSeconds), format: .time(pattern: .minuteSecond))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Stop dictation")
        } else {
            Button("Dictate", systemImage: "mic") {
                isBodyFocused = false
                draft.dictation = .sample
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
    }

    // MARK: Photos

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photoMessage {
                Text(photoMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    addPhotosButton
                    ForEach(draft.photos) { photo in
                        PhotoImage(data: photo.thumbnailData, cornerRadius: 14)
                            .frame(width: 64, height: 64)
                            .overlay(alignment: .topTrailing) {
                                // Removed from the draft only: the store changes on Save.
                                Button("Remove photo", systemImage: "xmark.circle.fill") {
                                    draft.removePhoto(photo.id)
                                }
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.8))
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                            }
                    }
                    ForEach(0..<pendingPhotoCount, id: \.self) { _ in
                        ProgressView()
                            .frame(width: 64, height: 64)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 14))
                            .accessibilityLabel("Adding photo")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Opens the photo library. Library only: there is no camera option.
    private var addPhotosButton: some View {
        PhotosPicker(
            selection: $pickerSelection,
            maxSelectionCount: draft.remainingPhotoSlots - pendingPhotoCount,
            selectionBehavior: .ordered,
            matching: .images,
            // Asks Photos for a converted copy, so RAW and other formats ImageIO can't
            // downsample arrive as something it can.
            preferredItemEncoding: .compatible
        ) {
            VStack(spacing: 3) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title3)
                Text("Add Photos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, height: 64)
            .background(.fill.tertiary, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        // One batch at a time, and never past the per-entry limit.
        .disabled(isProcessingPhotos || draft.remainingPhotoSlots == 0)
    }
}

/// The filled capsule behind the topic and date chips.
private struct ComposerChip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) {
            content
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(.fill.tertiary, in: .capsule)
        .contentShape(.capsule)
    }
}

/// Static bars standing in for a live input level.
private struct LevelMeter: View {
    private let heights: [CGFloat] = [6, 11, 16, 9, 18, 13, 7, 15, 20, 10, 14, 6, 12, 8]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}

/// Puts the topic under the navigation title, with its color dot.
private struct TopicSubtitle: ViewModifier {
    let topic: Topic?

    func body(content: Content) -> some View {
        if let topic {
            let dot = Text(Image(systemName: "circle.fill")).foregroundStyle(topic.tint)
            content.navigationSubtitle(Text("\(dot) \(topic.title)"))
        } else {
            content
        }
    }
}

#Preview("New from list") {
    ComposerPreview(state: .newFromList)
}

#Preview("New from list · Dark") {
    ComposerPreview(state: .newFromList)
        .preferredColorScheme(.dark)
}

#Preview("New in topic") {
    ComposerPreview(state: .newInTopic)
}

#Preview("Location · captured") {
    ComposerPreview(state: .newInTopic)
}

#Preview("Location · captured · Dark") {
    ComposerPreview(state: .newInTopic)
        .preferredColorScheme(.dark)
}

#Preview("Location · locating") {
    ComposerPreview(state: .newInTopic, location: FakeLocationService(delay: .seconds(600)))
}

#Preview("Location · no place name") {
    ComposerPreview(state: .newInTopic, location: FakeLocationService(failsGeocoding: true))
}

#Preview("Location · denied") {
    ComposerPreview(state: .newInTopic, location: FakeLocationService(location: .failure(.denied)))
}

#Preview("Location · unavailable") {
    ComposerPreview(
        state: .newInTopic, location: FakeLocationService(location: .failure(.unavailable))
    )
}

#Preview("Edit · dictation · photos") {
    ComposerPreview(state: .editDictating)
}

#Preview("Edit · dictation · photos · Dark") {
    ComposerPreview(state: .editDictating)
        .preferredColorScheme(.dark)
}

/// The design's composer frames, presented as sheets.
private struct ComposerPreview: View {
    enum PreviewState {
        case newFromList
        case newInTopic
        case editDictating
    }

    let state: PreviewState
    /// Decides what the location chip shows. "Sedona trip" captures location by default.
    var location = FakeLocationService()

    var body: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                composer
            }
            .sampleData(location: location)
    }

    @ViewBuilder private var composer: some View {
        switch state {
        case .newFromList:
            EntryComposerView(mode: .newFromList, now: SampleData.now, draft: stoicDraft)
        case .newInTopic:
            if let topic = PreviewContainer.topic("Sedona trip") {
                EntryComposerView(mode: .newInTopic(topic), now: SampleData.now)
            }
        case .editDictating:
            if let entry = PreviewContainer.entry(in: "Sedona trip", at: 2) {
                EntryComposerView(
                    mode: .edit(entry),
                    now: SampleData.now,
                    draft: dictationDraft(for: entry)
                )
            }
        }
    }

    private var stoicDraft: EntryDraft {
        var draft = EntryDraft(mode: .newFromList, now: SampleData.date(2026, 10, 5, 6, 42))
        draft.topic = PreviewContainer.topic("Stoic practice")
        draft.body = PreviewContainer.entry(in: "Stoic practice", at: 4)?.body ?? ""
        return draft
    }

    private func dictationDraft(for entry: Entry) -> EntryDraft {
        var draft = EntryDraft(mode: .edit(entry), now: SampleData.now)
        draft.date = SampleData.date(2026, 10, 2, 7, 48)
        draft.body =
            "Back at the car. Cathedral Rock took about ninety minutes up and down. The last "
            + "scramble is steeper than it looks from the lot, "
        draft.photos = entry.sortedPhotos.prefix(2).map(DraftPhoto.existing)
        draft.dictation = .sample
        return draft
    }
}
