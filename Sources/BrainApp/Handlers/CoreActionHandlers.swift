import Foundation
import BrainCore
import GRDB
import os.log

// MARK: - Handler factory

// Creates all core action handlers for use with ActionDispatcher.
enum CoreActionHandlers {
    @MainActor static func all(data: any DataProviding, emailBridge: EmailBridge? = nil) -> [any ActionHandler] {
        let email = emailBridge ?? EmailBridge(pool: data.databasePool)
        return [
            // Entry CRUD actions
            EntryCreateHandler(data: data),
            EntryUpdateHandler(data: data),
            EntryDeleteHandler(data: data),
            EntrySearchHandler(data: data),
            EntryMarkDoneHandler(data: data),
            EntryArchiveHandler(data: data),
            EntryRestoreHandler(data: data),
            EntryListHandler(data: data),
            EntryFetchHandler(data: data),
            // Link actions
            LinkCreateHandler(data: data),
            LinkDeleteHandler(data: data),
            LinkedEntriesHandler(data: data),
            // Tag actions
            TagAddHandler(data: data),
            TagRemoveHandler(data: data),
            TagListHandler(data: data),
            TagCountsHandler(data: data),
            // Search actions
            SearchAutocompleteHandler(data: data),
            // Knowledge actions
            KnowledgeSaveHandler(data: data),
            // Calendar actions
            CalendarListHandler(),
            CalendarCreateHandler(),
            CalendarDeleteHandler(),
            // Reminder actions
            ReminderSetHandler(data: data),
            ReminderCancelHandler(data: data),
            ReminderCancelAllHandler(),
            ReminderPendingCountHandler(),
            ReminderListHandler(),
            // Contact actions
            ContactLoadHandler(),
            ContactSearchHandler(),
            ContactReadHandler(),
            ContactCreateHandler(),
            ContactDeleteHandler(),
            ContactMergeHandler(),
            ContactDuplicatesHandler(),
            // Spotlight actions
            SpotlightIndexHandler(data: data),
            SpotlightDeindexHandler(),
            // Skill actions
            SkillCreateHandler(data: data),
            SkillListHandler(data: data),
            SkillInstallHandler(data: data),
            // AI-powered actions
            AISummarizeHandler(data: data),
            AIExtractTasksHandler(data: data),
            AIBriefingHandler(data: data),
            AIDraftReplyHandler(data: data),
            CrossRefHandler(data: data),
            // Self-Modifier actions
            RulesEvaluateHandler(data: data),
            ProposalListHandler(data: data),
            ProposalApplyHandler(data: data),
            // Email actions
            EmailListHandler(bridge: email),
            EmailFetchHandler(bridge: email),
            EmailSearchHandler(bridge: email),
            EmailMarkReadHandler(bridge: email),
            EmailSendHandler(bridge: email),
            EmailSyncHandler(bridge: email),
            EmailConfigureHandler(bridge: email),
            EmailMoveHandler(bridge: email),
            EmailSpamCheckHandler(bridge: email),
            EmailRescueSpamHandler(bridge: email),
            EmailReadHandler(bridge: email),
            EmailDeleteHandler(bridge: email),
            EmailReplyHandler(bridge: email),
            EmailForwardHandler(bridge: email),
            EmailFlagHandler(bridge: email),
            // Entry aliases (ARCHITECTURE.md names)
            EntryReadHandler(data: data),
            EntryToggleHandler(data: data),
            // File operations
            FileReadHandler(),
            FileWriteHandler(),
            FileDeleteHandler(),
            FileShareHandler(),
            // HTTP operations
            HTTPRequestHandler(),
            HTTPDownloadHandler(),
            // Local storage
            StorageGetHandler(),
            StorageSetHandler(),
            StorageDeleteHandler(),
            // UI dialogs
            AlertHandler(),
            ConfirmHandler(),
            NavigateBackHandler(),
            NavigateTabHandler(),
            SheetOpenHandler(),
            SheetCloseHandler(),
            // Clipboard
            ClipboardPasteHandler(),
            // Calendar update
            CalendarUpdateHandler(),
            // Contact update
            ContactUpdateHandler(),
            // Spotlight remove
            SpotlightRemoveHandler(),
            // LLM primitives
            LLMCompleteHandler(data: data),
            LLMStreamHandler(data: data),
            LLMEmbedHandler(data: data),
            LLMClassifyHandler(data: data),
            LLMExtractHandler(data: data),
            // Camera actions
            CameraCaptureHandler(),
            PhotoPickHandler(),
            // Audio actions
            AudioRecordHandler(),
            AudioPlayHandler(),
            // Health actions
            HealthReadHandler(),
            HealthWriteHandler(),
            // Scanner + extraction actions
            ScanTextHandler(),
            ExtractContactHandler(),
            ExtractReceiptHandler(),
            // NFC actions
            NFCReadHandler(),
            NFCWriteHandler(),
            // Bluetooth actions
            BluetoothScanHandler(),
            BluetoothConnectHandler(),
            // HomeKit actions
            HomeSceneHandler(),
            HomeDeviceHandler(),
            // Location geofence
            LocationGeofenceHandler(),
            // Speech actions
            SpeechRecognizeHandler(),
            SpeechTranscribeFileHandler(),
            // Pencil actions
            PencilRecognizeHandler(),
            // System & UI actions
            NavigateToHandler(),
            EntryOpenHandler(),
            ShareHandler(),
            HapticHandler(),
            ClipboardCopyHandler(),
            OpenURLHandler(),
            ToastHandler(),
            SetVariableHandler(),
            // Location (from LocationBridge.swift)
            LocationCurrentHandler(),
            // Semantic Search
            SemanticSearchHandler(data: data),
            EntrySimilarHandler(data: data),
            // Conversation Memory
            MemorySearchPersonHandler(data: data),
            MemorySearchTopicHandler(data: data),
            MemoryFactsHandler(data: data),
            UserProfileHandler(data: data),
            // On This Day
            OnThisDayHandler(data: data),
            // Backup
            BackupExportHandler(data: data),
            // Proposals
            ProposalRejectHandler(data: data),
            // Image analysis (text detection, contour tracing, SVG generation)
            ImageDetectTextHandler(),
            ImageTraceContoursHandler(),
            SVGGenerateHandler(),
            // Signal analysis (audio amplitude, visual brightness)
            SignalAnalyzeAudioHandler(),
            SignalAnalyzeBrightnessHandler(),
            // Morse code (codec + convenience handlers)
            MorseDecodeHandler(),
            MorseEncodeHandler(),
            MorseDecodeAudioHandler(),
            MorseDecodeVisualHandler(),
            // Sensor data (Phyphox-style raw sensor access)
            SensorAccelerometerHandler(),
            SensorGyroscopeHandler(),
            SensorMagnetometerHandler(),
            SensorBarometerHandler(),
            SensorDeviceMotionHandler(),
            SensorProximityHandler(),
            SensorBatteryHandler(),
            // Audio analysis (Phyphox-style: FFT, pitch, oscilloscope, tone, sonar, Doppler)
            AudioAmplitudeHandler(),
            AudioSpectrumHandler(),
            AudioPitchHandler(),
            AudioOscilloscopeHandler(),
            AudioToneHandler(),
            AudioSonarHandler(),
            AudioFrequencyTrackHandler(),
            // Sensor spectrum (FFT on motion sensors)
            SensorAccSpectrumHandler(),
            SensorGyroSpectrumHandler(),
            SensorMagSpectrumHandler(),
            // Camera analysis (color, luminance, LiDAR depth)
            CameraColorHandler(),
            CameraLuminanceHandler(),
            CameraDepthHandler(),
            // Stopwatch experiments (event-triggered timing)
            StopwatchAcousticHandler(),
            StopwatchMotionHandler(),
            StopwatchOpticalHandler(),
            StopwatchProximityHandler(),
        ]
    }
}
