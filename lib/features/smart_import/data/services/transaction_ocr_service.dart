import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/ocr_result.dart';

/// Runs OCR on a screenshot/image. Kept as an interface — never referenced
/// directly by the transaction extractor or the review UI — so the OCR
/// vendor can be swapped (or a cloud fallback added later) without touching
/// any parsing logic.
abstract class TransactionOcrService {
  Future<OcrResult> extractText(File image);
}

/// On-device implementation via Google ML Kit's text recognizer. Runs fully
/// offline — the image never leaves the device — which is both a privacy
/// requirement (these are financial screenshots) and why Smart Import works
/// without a network connection.
class MlKitTransactionOcrService implements TransactionOcrService {
  MlKitTransactionOcrService()
    : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  @override
  Future<OcrResult> extractText(File image) async {
    final inputImage = InputImage.fromFile(image);
    final recognized = await _recognizer.processImage(inputImage);

    final lines = <OcrTextLine>[
      for (final block in recognized.blocks)
        for (final line in block.lines)
          OcrTextLine(
            text: line.text,
            boundingBox: OcrBoundingBox(
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
            ),
            confidence: line.confidence,
          ),
    ];

    return OcrResult(fullText: recognized.text, lines: lines);
  }

  /// Releases the native recognizer. Call once the Smart Import flow is
  /// done (e.g. when its controller is disposed).
  Future<void> dispose() => _recognizer.close();
}
