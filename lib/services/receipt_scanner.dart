import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'receipt_parser.dart';

/// The plugin edge of receipt scanning: pick a bill photo (camera or gallery),
/// run on-device OCR over it, and hand the text to [ReceiptParser].
///
/// Kept thin and free of Flutter widgets so the pure-Dart parsing it delegates
/// to stays independently testable. Everything runs on-device; the image is
/// never uploaded.
class ReceiptScanner {
  ReceiptScanner._();

  static final ImagePicker _picker = ImagePicker();

  /// Picks an image from [source], recognizes its text, and parses it into a
  /// draft transaction, with the photo's path so it can be kept with the
  /// transaction. Returns null when the user cancels the picker.
  static Future<({ParsedReceipt receipt, String imagePath})?> scan(
      ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      // Downscale a little: OCR does not need full-resolution photos, and
      // smaller inputs are faster to process.
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (file == null) return null;

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(file.path);
      final recognized = await recognizer.processImage(input);
      return (
        receipt: ReceiptParser.parse(recognized.text),
        imagePath: file.path
      );
    } finally {
      await recognizer.close();
    }
  }

  /// Picks a photo to keep with a transaction, without reading it. Null when
  /// the user cancels.
  static Future<String?> pickPhoto(ImageSource source) async {
    final file = await _picker.pickImage(
        source: source, imageQuality: 80, maxWidth: 1600);
    return file?.path;
  }
}
