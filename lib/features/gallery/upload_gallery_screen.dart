import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_error.dart';
import '../../shared/widgets/upgrade_dialog.dart';
import '../../features/auth/presentation/auth_provider.dart' show dioClientProvider;

class UploadGalleryScreen extends ConsumerStatefulWidget {
  final String tripId;
  const UploadGalleryScreen({super.key, required this.tripId});

  @override
  ConsumerState<UploadGalleryScreen> createState() => _UploadGalleryScreenState();
}

class _UploadGalleryScreenState extends ConsumerState<UploadGalleryScreen> {
  final List<XFile> _selected = [];
  final Map<int, Uint8List> _thumbBytes = {};
  final _captionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _albumCtrl = TextEditingController();
  bool _uploading = false;
  double _progress = 0;
  String _fileType = 'PHOTO';

  final _picker = ImagePicker();

  @override
  void dispose() {
    _captionCtrl.dispose();
    _locationCtrl.dispose();
    _albumCtrl.dispose();
    super.dispose();
  }

  Dio get _dio => ref.read(dioClientProvider).dio;

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage(
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    for (final img in images) {
      final idx = _selected.length;
      _selected.add(img);
      _loadThumb(idx, img);
    }
    setState(() => _fileType = 'PHOTO');
  }

  Future<void> _pickVideo() async {
    final video = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    if (video != null) {
      final idx = _selected.length;
      _selected.add(video);
      _loadThumb(idx, video);
      setState(() => _fileType = 'VIDEO');
    }
  }

  Future<void> _takePhoto() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (photo != null) {
      final idx = _selected.length;
      _selected.add(photo);
      _loadThumb(idx, photo);
      setState(() => _fileType = 'PHOTO');
    }
  }

  Future<void> _loadThumb(int idx, XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _thumbBytes[idx] = bytes);
    } catch (_) {}
  }

  void _remove(int index) {
    setState(() => _selected.removeAt(index));
  }

  String _cloudFolder() => 'tripmate/${widget.tripId}';

  Future<void> _upload() async {
    if (_selected.isEmpty) return;
    setState(() { _uploading = true; _progress = 0; });

    for (var i = 0; i < _selected.length; i++) {
      final file = _selected[i];
      try {
        final bytes = await file.readAsBytes();
        final fileName = file.name;
        final isVideo = file.mimeType?.startsWith('video') == true ||
            file.path.toLowerCase().endsWith('.mp4') ||
            file.path.toLowerCase().endsWith('.mov');

        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
          'folder': _cloudFolder(),
        });

        final res = await _dio.post(
          '/api/files/upload-cloudinary',
          data: formData,
          onSendProgress: (sent, total) {
            if (total > 0) {
              setState(() => _progress = ((i + sent / total) / _selected.length));
            }
          },
        );

        final data = res.data['data'];
        final url = data['url'] ?? '';
        final thumb = data['thumbnailUrl'] ?? url;
        final fileBytes = data['bytes'];

        final fileType = isVideo ? 'VIDEO' : _fileType;

        await _dio.post('/api/trips/${widget.tripId}/gallery', data: {
          'cloudinaryUrl': url,
          'thumbnailUrl': thumb,
          'fileType': fileType,
          'fileSizeBytes': fileBytes?.toString(),
          'caption': _captionCtrl.text.trim().isNotEmpty ? _captionCtrl.text.trim() : null,
          'locationName': _locationCtrl.text.trim().isNotEmpty ? _locationCtrl.text.trim() : null,
          'albumName': _albumCtrl.text.trim().isNotEmpty ? _albumCtrl.text.trim() : null,
        });
      } catch (e) {
        if (mounted) {
          final msg = apiErrorMessage(e);
          if (isLimitMessage(msg)) {
            showLimitUpgradeDialog(context, msg, title: 'Storage full');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed: ${file.name} — $msg'),
                  backgroundColor: Colors.red),
            );
          }
        }
      }
    }

    if (mounted) {
      setState(() { _uploading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_selected.length} memories uploaded!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: const Text('Upload Memories'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _uploading
          ? _buildProgress()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Capture & Share', style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary(context))),
                  const SizedBox(height: 6),
                  Text('Upload photos and videos from your trip',
                      style: TextStyle(color: AppColors.textSecondary(context))),
                  const SizedBox(height: 24),
                  _uploadOption(Icons.camera_alt, 'Take Photo', 'Use camera', _takePhoto),
                  const SizedBox(height: 12),
                  _uploadOption(Icons.photo_library, 'Select Photos', 'From gallery', _pickImages),
                  const SizedBox(height: 12),
                  _uploadOption(Icons.videocam, 'Upload Video', 'Max 5 min', _pickVideo),
                  if (_selected.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Selected (${_selected.length})',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selected.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: _thumbBytes[i] != null
                                    ? Image.memory(_thumbBytes[i]!,
                                        width: 90, height: 90, fit: BoxFit.cover)
                                    : Container(
                                        width: 90, height: 90,
                                        color: AppColors.card(context),
                                        child: Icon(Icons.image, color: AppColors.textMuted(context)),
                                      ),
                              ),
                              Positioned(
                                top: 4, right: 4,
                                child: GestureDetector(
                                  onTap: () => _remove(i),
                                  child: Container(
                                    width: 22, height: 22,
                                    decoration: const BoxDecoration(
                                        color: Colors.red, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextField(
                    controller: _captionCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Add a caption...',
                      filled: true,
                      fillColor: AppColors.inputFill(context),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locationCtrl,
                    decoration: InputDecoration(
                      hintText: 'Tag location',
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                      filled: true,
                      fillColor: AppColors.inputFill(context),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _albumCtrl,
                    decoration: InputDecoration(
                      hintText: 'Album name (optional)',
                      prefixIcon: const Icon(Icons.folder_outlined, size: 20),
                      filled: true,
                      fillColor: AppColors.inputFill(context),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _selected.isEmpty ? null : _upload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Upload Memories',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _uploadOption(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.blue, size: 26),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
              ],
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: AppColors.textSecondary(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80, height: 80,
              child: CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
                strokeWidth: 4,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(height: 24),
            Text('Uploading memories...', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
            const SizedBox(height: 8),
            Text('${(_progress * 100).toInt()}%', style: TextStyle(
                fontSize: 14, color: AppColors.textSecondary(context))),
          ],
        ),
      ),
    );
  }
}
