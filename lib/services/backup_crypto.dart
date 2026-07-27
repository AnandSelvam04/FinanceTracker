import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Passphrase-based AES-GCM encryption for backup files. Produces a
/// self-describing JSON envelope so a restore can detect an encrypted backup
/// and decrypt it. The passphrase is never stored; a forgotten passphrase
/// means the backup cannot be recovered (by design).
class BackupCrypto {
  static const _magic = 'ft-enc-v1';

  /// PBKDF2 iterations for **new** backups, raised from 100,000.
  ///
  /// Deliberately short of OWASP's 600,000 for PBKDF2-HMAC-SHA256. This is a
  /// pure-Dart KDF, and 600,000 measures ~3s on a fast desktop, so a
  /// mid-range phone would sit for ten seconds or more on every encrypt *and*
  /// every decrypt — slow enough that users avoid encrypted backups
  /// altogether. 210,000 keeps that near a second on desktop while more than
  /// doubling the work factor.
  ///
  /// The bigger win is elsewhere: the minimum passphrase went from 4
  /// characters to 12, and against offline brute force passphrase entropy
  /// dominates the iteration count. Raising this further is worth doing
  /// alongside a native KDF (Argon2id via a plugin), where the cost is
  /// affordable.
  ///
  /// Safe to change at any time because the count travels in the envelope and
  /// [decryptString] honours whatever a given file was written with — see
  /// [_iterationsFrom]. Older backups keep working at their original count.
  static const _iterations = 210000;

  /// Count used for envelopes written before the `iterations` field was
  /// respected on read. Those files are all 100,000.
  static const _legacyIterations = 100000;

  /// Guard against a hostile or corrupt envelope specifying an absurd count
  /// and hanging the app in key derivation.
  static const _maxIterations = 5000000;

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
      throw FormatException('Not a valid encrypted backup');
    }
    if (map['magic'] != _magic) {
      throw FormatException('Not an encrypted Finance Tracker backup');
    }
    final salt = base64Decode(map['salt'] as String);
    final nonce = base64Decode(map['nonce'] as String);
    final ct = base64Decode(map['ct'] as String);
    final mac = base64Decode(map['mac'] as String);
    // Derive with the count this envelope was written with, not the current
    // constant — otherwise raising _iterations would make every existing
    // backup undecryptable.
    final key =
        await _deriveKey(passphrase, salt, _iterationsFrom(map['iterations']));
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

  /// The iteration count to decrypt with, taken from the envelope.
  ///
  /// A missing or unusable field means the file predates this being written
  /// out and read back, so it is a 100,000-iteration envelope.
  static int _iterationsFrom(Object? raw) {
    if (raw is! int || raw < 1) return _legacyIterations;
    if (raw > _maxIterations) {
      throw FormatException(
          'Encrypted backup asks for an implausible iteration count ($raw)');
    }
    return raw;
  }

  static Future<SecretKey> _deriveKey(String passphrase, List<int> salt,
      [int iterations = _iterations]) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static Uint8List _randomBytes(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  }
}
