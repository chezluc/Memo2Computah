import Foundation
import whisper

enum LocalWhisperError: LocalizedError {
    case modelNotFound
    case couldNotLoadModel
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "The local Whisper model was not found in the app bundle."
        case .couldNotLoadModel:
            return "The local Whisper model could not be loaded."
        case .transcriptionFailed:
            return "Local Whisper transcription failed."
        }
    }
}

actor LocalWhisperTranscriber {
    private var context: OpaquePointer?

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    func transcribe(fileURL: URL) throws -> String {
        let context = try loadedContext()
        let samples = try decodeWaveFile(fileURL)
        guard !samples.isEmpty else {
            throw LocalWhisperError.transcriptionFailed
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        params.n_threads = Int32(max(1, min(6, ProcessInfo.processInfo.processorCount - 2)))
        params.language = nil

        let result = samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }
        guard result == 0 else {
            throw LocalWhisperError.transcriptionFailed
        }

        var transcript = ""
        for index in 0..<whisper_full_n_segments(context) {
            transcript += String(cString: whisper_full_get_segment_text(context, index))
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadedContext() throws -> OpaquePointer {
        if let context {
            return context
        }

        guard let modelURL = Self.modelURL else {
            throw LocalWhisperError.modelNotFound
        }

        var params = whisper_context_default_params()
#if targetEnvironment(simulator)
        params.use_gpu = false
#else
        params.flash_attn = true
#endif

        guard let loaded = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw LocalWhisperError.couldNotLoadModel
        }
        context = loaded
        return loaded
    }

    private static var modelURL: URL? {
        Bundle.main.url(forResource: "ggml-tiny", withExtension: "bin", subdirectory: "models")
            ?? Bundle.main.url(forResource: "ggml-tiny", withExtension: "bin", subdirectory: "Resources/models")
            ?? Bundle.main.url(forResource: "ggml-tiny", withExtension: "bin")
    }

    private func decodeWaveFile(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else { return [] }

        return stride(from: 44, to: data.count - 1, by: 2).map { offset in
            data[offset..<(offset + 2)].withUnsafeBytes { bytes in
                let sample = Int16(littleEndian: bytes.load(as: Int16.self))
                return max(-1.0, min(Float(sample) / 32767.0, 1.0))
            }
        }
    }
}
