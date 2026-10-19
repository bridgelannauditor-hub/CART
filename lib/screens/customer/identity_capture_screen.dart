import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../repositories/seller_application_repository.dart';

/// Guided camera capture for Seller identity verification: the ID (front, and
/// back when the ID has one) and a selfie. The photos are uploaded to a
/// private bucket and queued for manual review by an administrator.
///
/// Pops with `true` once the photos were submitted.
class IdentityCaptureScreen extends StatefulWidget {
  const IdentityCaptureScreen({super.key});

  @override
  State<IdentityCaptureScreen> createState() => _IdentityCaptureScreenState();
}

class _IdentityCaptureScreenState extends State<IdentityCaptureScreen> {
  final _repository = SellerApplicationRepository();
  final _picker = ImagePicker();

  String? _documentType;
  String? _loadError;

  File? _front;
  File? _back;
  File? _selfie;
  bool _submitting = false;

  static const _documentLabels = {
    'national_id': 'National ID',
    'passport': 'Passport',
    'drivers_license': "Driver's license",
    'student_id': 'Student ID',
  };

  bool get _needsBack => _documentType != 'passport';

  bool get _complete =>
      _front != null && _selfie != null && (!_needsBack || _back != null);

  @override
  void initState() {
    super.initState();
    _loadDocumentType();
  }

  Future<void> _loadDocumentType() async {
    try {
      final type = await _repository.identityDocumentType();
      if (mounted) setState(() => _documentType = type);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Your application could not be loaded.');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _capture(
    ValueSetter<File> assign, {
    required bool selfie,
  }) async {
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
      );
      if (shot == null || !mounted) return;
      setState(() => assign(File(shot.path)));
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.code.contains('denied')
            ? 'Camera access is off. Allow the camera for C+ART in your '
                  'phone settings, then try again.'
            : 'The camera could not be opened. Please try again.',
      );
    } catch (_) {
      if (mounted) _showMessage('The camera could not be opened.');
    }
  }

  Future<void> _submit() async {
    if (!_complete || _submitting) return;
    setState(() => _submitting = true);
    try {
      await _repository.submitIdentityDocuments(
        front: _front!,
        back: _needsBack ? _back : null,
        selfie: _selfie!,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on StorageException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.statusCode == '404' || error.message.contains('not found')
            ? 'Photo upload is not set up yet. Please contact support.'
            : 'The photos could not be uploaded. Check your connection and '
                  'try again.',
      );
    } on PostgrestException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage('The photos could not be sent. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docLabel = _documentLabels[_documentType] ?? 'ID';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Verify your identity')),
      body: _loadError != null
          ? Center(child: Text(_loadError!))
          : _documentType == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const _TipsCard(),
                const SizedBox(height: 20),
                _PhotoSlot(
                  step: 1,
                  title: 'Front of your $docLabel',
                  hint:
                      'Place it on a flat surface. All four corners and '
                      'the text must be visible.',
                  icon: Icons.badge_outlined,
                  file: _front,
                  enabled: !_submitting,
                  onCapture: () =>
                      _capture((file) => _front = file, selfie: false),
                ),
                if (_needsBack) ...[
                  const SizedBox(height: 16),
                  _PhotoSlot(
                    step: 2,
                    title: 'Back of your $docLabel',
                    hint: 'Same rules: flat, bright, no glare.',
                    icon: Icons.flip_outlined,
                    file: _back,
                    enabled: !_submitting,
                    onCapture: () =>
                        _capture((file) => _back = file, selfie: false),
                  ),
                ],
                const SizedBox(height: 16),
                _PhotoSlot(
                  step: _needsBack ? 3 : 2,
                  title: 'Selfie',
                  hint:
                      'Face the camera in good light, without a hat or '
                      'sunglasses, so we can match you to your ID.',
                  icon: Icons.face_retouching_natural_outlined,
                  file: _selfie,
                  enabled: !_submitting,
                  round: true,
                  onCapture: () =>
                      _capture((file) => _selfie = file, selfie: true),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _complete && !_submitting ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'SUBMIT FOR REVIEW',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your photos are stored privately and are only seen by '
                  'C+ART administrators to verify who you are. Seller tools '
                  'unlock after they approve your application.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    const tips = [
      'Use a valid, unexpired government or school ID.',
      'Take the photos in bright light and avoid glare.',
      'Keep your hand and phone steady so the text is sharp.',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tip, style: const TextStyle(height: 1.3)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  final int step;
  final String title;
  final String hint;
  final IconData icon;
  final File? file;
  final bool enabled;
  final bool round;
  final VoidCallback onCapture;

  const _PhotoSlot({
    required this.step,
    required this.title,
    required this.hint,
    required this.icon,
    required this.file,
    required this.enabled,
    required this.onCapture,
    this.round = false,
  });

  @override
  Widget build(BuildContext context) {
    final taken = file != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: taken ? AppColors.success : AppColors.lightGrey,
          width: taken ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: taken ? AppColors.success : AppColors.primary,
                child: taken
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        '$step',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: enabled ? onCapture : null,
              child: _Preview(
                icon: icon,
                file: file,
                round: round,
                label: taken ? 'Tap to retake' : 'Tap to open camera',
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: enabled ? onCapture : null,
              icon: Icon(
                taken ? Icons.refresh_rounded : Icons.photo_camera_outlined,
              ),
              label: Text(taken ? 'Retake photo' : 'Take photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final IconData icon;
  final File? file;
  final bool round;
  final String label;

  const _Preview({
    required this.icon,
    required this.file,
    required this.round,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    // ID cards are ~1.58:1; the selfie preview is a circle.
    final width = round ? 160.0 : double.infinity;
    final aspect = round ? 1.0 : 1.58;

    final content = file != null
        ? Image.file(file!, fit: BoxFit.cover)
        : Container(
            color: AppColors.lightGrey.withValues(alpha: 0.45),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 42, color: AppColors.primary),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          );

    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: aspect,
        child: round
            ? ClipOval(child: content)
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: content,
              ),
      ),
    );
  }
}
