import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../../core/constants/app_colors.dart';
import '../../features/auth/presentation/auth_provider.dart'
    show dioClientProvider;

class PhotoDetailScreen extends ConsumerStatefulWidget {
  final String itemId;
  final String tripId;
  const PhotoDetailScreen({
    super.key,
    required this.itemId,
    required this.tripId,
  });

  @override
  ConsumerState<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends ConsumerState<PhotoDetailScreen> {
  Map<String, dynamic>? _item;
  bool _loading = true;
  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Dio get _dio => ref.read(dioClientProvider).dio;

  Future<void> _load() async {
    try {
      final res = await _dio.get(
        '/api/trips/${widget.tripId}/gallery/${widget.itemId}',
      );
      if (!mounted) return;
      setState(() {
        _item = Map<String, dynamic>.from(res.data['data']);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike() async {
    try {
      final res = await _dio.post(
        '/api/trips/${widget.tripId}/gallery/${widget.itemId}/like',
      );
      if (!mounted) return;
      final liked = res.data['data']['liked'] as bool;
      setState(() {
        _item?['likedByMe'] = liked;
        _item?['likeCount'] = (_item?['likeCount'] ?? 0) + (liked ? 1 : -1);
      });
    } catch (_) {}
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await _dio.post(
        '/api/trips/${widget.tripId}/gallery/${widget.itemId}/comments',
        data: {'text': text},
      );
      _commentCtrl.clear();
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Photo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _item != null ? () => _showShareSheet(context) : null,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _item != null ? () => _download() : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _item == null
          ? Center(
              child: Text(
                'Not found',
                style: TextStyle(color: AppColors.textMuted(context)),
              ),
            )
          : _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final url = (_item!['cloudinaryUrl'] ?? '').toString();
    final caption = (_item!['caption'] ?? '').toString();
    final location = (_item!['locationName'] ?? '').toString();
    final userName = ((_item!['user']?['name'] ?? '')).toString().trim();
    final createdAt = _item!['createdAt']?.toString() ?? '';
    final likeCount = _item!['likeCount'] ?? 0;
    final liked = _item!['likedByMe'] ?? false;
    final comments = (_item!['comments'] as List?) ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.45,
            width: double.infinity,
            child: InteractiveViewer(
              // Single-finger drag scrolls the page; pinch still zooms.
              panEnabled: false,
              scaleEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => Icon(
                    Icons.broken_image,
                    color: AppColors.textMuted(context),
                    size: 60,
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: AppColors.card(context),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.blue.withValues(alpha: 0.2),
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName.isNotEmpty ? userName : 'Unknown',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          if (createdAt.isNotEmpty)
                            Text(
                              _formatDate(createdAt),
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    caption,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                    ),
                  ),
                ],
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: AppColors.textSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        location,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleLike,
                      child: Row(
                        children: [
                          Icon(
                            liked ? Icons.favorite : Icons.favorite_border,
                            color: liked
                                ? Colors.red
                                : AppColors.textSecondary(context),
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$likeCount',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.textSecondary(context),
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${comments.length}',
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final c in comments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (((c['user']?['name'] ?? '')).toString().trim())
                                  .isNotEmpty
                              ? ((c['user']?['name'] ?? '')).toString().trim()
                              : 'User',
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            (c['text'] ?? '').toString(),
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        style: TextStyle(color: AppColors.textPrimary(context)),
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: TextStyle(
                            color: AppColors.textMuted(context),
                          ),
                          filled: true,
                          fillColor: AppColors.inputFill(context),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _addComment,
                      icon: const Icon(
                        Icons.send,
                        color: AppColors.blue,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('d MMM yyyy').format(dt);
    } catch (_) {
      return iso;
    }
  }

  void _download() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Download started...')));
  }

  void _showShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Share Photo',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 16),
            _shareOption(
              context,
              Icons.link,
              'Copy Link',
              () => Navigator.pop(context),
            ),
            _shareOption(
              context,
              Icons.chat,
              'WhatsApp',
              () => Navigator.pop(context),
            ),
            _shareOption(
              context,
              Icons.send,
              'Telegram',
              () => Navigator.pop(context),
            ),
            _shareOption(
              context,
              Icons.email,
              'Email',
              () => Navigator.pop(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _shareOption(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary(context)),
      title: Text(
        label,
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      onTap: onTap,
    );
  }
}
