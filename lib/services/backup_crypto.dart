import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../l10n/app_localizations.dart';

/// Passphrase-based AES-GCM encryption for backup files. Produces a
/// self-describing JSON envelope so a restore can detect an encrypted backup
/// and decrypt it. The passphrase is never stored; a forgotten passphrase
/// means the backup cannot be recovered (by design).
class BackupCrypto {
  static const _magic = 'ft-enc-v1';
  static const _iterations = 100000;
  static final AesGcm _algo = AesGcm.with256bits();

  /// Encrypts [plaintext] with [passphrase], returning a JSON envelope string.
  static Future<String> encryptString(
      String plaintext, String passphrase) async {
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveKey(passphrase, salt);
    final box = await _algo.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'magic': _magic,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ct': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  /// Decrypts an [envelope] produced by [encryptString]. Throws if the
  /// passphrase is wrong, the data is corrupt, or it isn't an encrypted backup.
  static Future<String> decryptString(
      String envelope, String passphrase) async {
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(envelope) as Map<String, dynamic>;
    } catch (_) {
      throw FormatException(AppLocalizations.resolve().notValidEncryptedBackup);
    }
    if (map['magic'] != _magic) {
      throw FormatException(
          AppLocalizations.resolve().notFinanceTrackerBackup);
    }
    final salt = base64Decode(map['salt'] as String);
    final nonce = base64Decode(map['nonce'] as String);
    final ct = base64Decode(map['ct'] as String);
    final mac = base64Decode(map['mac'] as String);
    final key = await _deriveKey(passphrase, salt);
    final clear = await _algo.decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  /// Whether [content] looks like an encrypted backup envelope.
  static bool isEncrypted(String content) {
    try {
      final map = jsonDecode(content);
      return map is Map && map['magic'] == _magic;
    } catch (_) {
      return false;
    }
  }

  static Future<SecretKey> _deriveKey(String passphrase, List<int> salt) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static Uint8List _randomBytes(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  }
}
