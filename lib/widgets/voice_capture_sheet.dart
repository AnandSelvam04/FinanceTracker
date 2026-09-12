import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../utils/app_colors.dart';
import '../utils/insets.dart';

/// Opens the voice capture sheet and resolves to the recognized sentence, or
/// null if the user dismissed it without a usable result.
Future<String?> showVoiceCaptureSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _VoiceCaptureSheet(),
  );
}

/// A microphone sheet that live-transcribes speech and returns the words for
/// [VoiceExpenseParser] to interpret into a draft expense.
class _VoiceCaptureSheet extends StatefulWidget {
  const _VoiceCaptureSheet();

  @override
  State<_VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<_VoiceCaptureSheet> {
  final SpeechToText _speech = SpeechToText();
  String _words = '';
  bool _listening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    // Best-effort stop; the plugin tolerates being stopped when idle.
    _speech.stop();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
      );
      if (!mounted) return;
      if (available) {
        _startListening();
      } else {
        setState(() => _error =
            'Speech recognition is not available. Check the microphone '
            'permission in system settings.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the microphone.');
    }
  }

  void _onStatus(String status) {
    if (!mounted) return;
    if (status == 'done' || status == 'notListening') {
      setState(() => _listening = false);
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _listening = false;
      // Only surface a hard failure; a "no match" just means try again.
      if (error.errorMsg != 'error_no_match') {
        _error = 'Microphone error: ${error.errorMsg}';
      }
    });
  }

  Future<void> _startListening() async {
    setState(() {
      _words = '';
      _error = null;
      _listening = true;
    });
    await _speech.listen(
      onResult: _onResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      _words = result.recognizedWords;
      if (result.finalResult) _listening = false;
    });
  }

  Future<void> _stop() async {
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: bottomSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Add by voice',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Try: “spent 250 on food at Dominos”',
              style: TextStyle(color: mutedTextColor(context), fontSize: 13)),
          const SizedBox(height: 20),
          // Tap to restart listening; the icon fills while the mic is live.
          GestureDetector(
            onTap: _listening ? _stop : _startListening,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _listening
                    ? scheme.primary
                    : scheme.primary.withValues(alpha: 0.15),
              ),
              child: Icon(
                _listening ? Icons.mic : Icons.mic_none,
                size: 40,
                color: _listening ? scheme.onPrimary : scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _listening ? 'Listening…' : 'Tap the mic to speak',
            style: TextStyle(color: mutedTextColor(context)),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: expenseColor(context))),
            )
          else
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _words.isEmpty ? 'Your words will appear here' : _words,
                style: TextStyle(
                  fontSize: 16,
                  color: _words.isEmpty
                      ? mutedTextColor(context)
                      : scheme.onSurface,
                ),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _words.trim().isEmpty
                      ? null
                      : () {
                          _speech.stop();
                          Navigator.pop(context, _words.trim());
                        },
                  icon: const Icon(Icons.check),
                  label: const Text('Use'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
