import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_error.dart';
import '../../features/auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../shared/widgets/not_member_card.dart';
import '../../shared/widgets/top_bar.dart' show DarkModeToggle, NotificationsButton;
import '../../shared/widgets/trip_selector_sheet.dart';
import 'photo_detail_screen.dart';
import 'upload_gallery_screen.dart';

class TripGalleryScreen extends ConsumerStatefulWidget {
  final String tripId;
  const TripGalleryScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripGalleryScreen> createState() => _TripGalleryScreenState();
}

class _TripGalleryScreenState extends ConsumerState<TripGalleryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  bool _notMember = false;
  Map<String, dynamic>? _meta;
  List<Map<String, dynamic>> _photos = [];
  List<Map<String, dynamic>> _albums = [];
  List<Map<String, dynamic>> _contributors = [];
  Map<String, dynamic>? _stats;
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  String _activeTab = 'photos';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      final tabNames = ['photos', 'videos', 'albums'];
      final newTab = tabNames[_tabs.index];
      if (newTab != _activeTab) {
        setState(() => _activeTab = newTab);
        _page = 0;
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TripGalleryScreen old) {
    super.didUpdateWidget(old);
    if (old.tripId != widget.tripId) {
      // Trip switched: drop stale data, show loader while new data loads.
      setState(() {
        _loading = true;
        _loadingMore = false;
        _notMember = false;
        _photos = [];
        _albums = [];
        _contributors = [];
        _stats = null;
        _meta = null;
        _page = 0;
        _hasMore = true;
      });
      _load();
    }
  }

  Dio get _dio => ref.read(dioClientProvider).dio;

  Future<void> _load() async {
    if (_activeTab == 'albums') {
      await _loadAlbums();
      return;
    }
    try {
      final type = _activeTab == 'videos' ? 'VIDEO' : 'PHOTO';
      final res = await _dio.get('/api/trips/${widget.tripId}/gallery',
          queryParameters: {'type': type, 'page': 0, 'size': 30});
      if (!mounted) return;
      final data = res.data['data'];
      setState(() {
        _photos = (data['items'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
        _meta = Map<String, dynamic>.from(data['meta']);
        _hasMore = _meta!['hasMore'] ?? false;
        _page = 0;
        _loading = false;
        _notMember = false;
      });
      _loadStats();
      _loadContributors();
    } catch (e) {
      if (!mounted) return;
      if (isNotMemberError(e)) {
        setState(() { _notMember = true; _loading = false; });
      } else {
        setState(() { _loading = false; });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _activeTab == 'albums') return;
    setState(() => _loadingMore = true);
    try {
      final type = _activeTab == 'videos' ? 'VIDEO' : 'PHOTO';
      final res = await _dio.get('/api/trips/${widget.tripId}/gallery',
          queryParameters: {'type': type, 'page': _page + 1, 'size': 30});
      if (!mounted) return;
      final data = res.data['data'];
      final more = (data['items'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      setState(() {
        _photos.addAll(more);
        _page++;
        _hasMore = (data['meta']['hasMore'] ?? false);
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadAlbums() async {
    try {
      final res = await _dio.get('/api/trips/${widget.tripId}/gallery/albums');
      if (!mounted) return;
      setState(() {
        _albums = (res.data['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
        _notMember = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (isNotMemberError(e)) {
        setState(() { _notMember = true; _loading = false; });
      } else {
        setState(() { _loading = false; });
      }
    }
  }

  Future<void> _loadStats() async {
    try {
      final res = await _dio.get('/api/trips/${widget.tripId}/gallery/stats');
      if (mounted) setState(() => _stats = Map<String, dynamic>.from(res.data['data']));
    } catch (_) {}
  }

  Future<void> _loadContributors() async {
    try {
      final res = await _dio.get('/api/trips/${widget.tripId}/gallery/contributors');
      if (mounted) setState(() => _contributors = (res.data['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: TripDropdown(tripId: widget.tripId),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/trips/${widget.tripId}/map'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 22),
            onPressed: () => _showSearch(context),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 22),
            onPressed: () => _showMoreMenu(context),
          ),
          const DarkModeToggle(),
          const NotificationsButton(),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Photos'),
            Tab(text: 'Videos'),
            Tab(text: 'Albums'),
          ],
          labelColor: AppColors.blue,
          unselectedLabelColor: AppColors.textSecondary(context),
          indicatorColor: AppColors.blue,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notMember
              ? NotMemberCard(tripId: widget.tripId, onRetry: _load)
              : _buildBody(),
      floatingActionButton: _activeTab != 'albums'
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => UploadGalleryScreen(tripId: widget.tripId)));
                _page = 0;
                _load();
              },
              backgroundColor: AppColors.blue,
              icon: const Icon(Icons.add_a_photo, color: Colors.white),
              label: const Text('Upload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        if (_stats != null) _StorageBar(stats: _stats!),
        Expanded(
          child: _activeTab == 'albums'
              ? _AlbumsView(
                  albums: _albums,
                  tripId: widget.tripId,
                  onRefresh: () { _page = 0; _load(); },
                )
              : _photos.isEmpty
                  ? _EmptyGallery(onUpload: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => UploadGalleryScreen(tripId: widget.tripId)));
                      _page = 0;
                      _load();
                    })
                  : _PhotoGrid(
                      photos: _photos,
                      hasMore: _hasMore,
                      loadingMore: _loadingMore,
                      onRefresh: () async { _page = 0; await _load(); },
                      onLoadMore: _loadMore,
                      tripId: widget.tripId,
                    ),
        ),
        if (_contributors.isNotEmpty) _ContributorsRow(contributors: _contributors),
      ],
    );
  }

  void _showSearch(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search photos...',
                  prefixIcon: const Icon(Icons.search, size: 22),
                  filled: true,
                  fillColor: AppColors.inputFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) async {
                  Navigator.pop(context);
                  if (v.trim().isEmpty) return;
                  try {
                    final res = await _dio.get('/api/trips/${widget.tripId}/gallery',
                        queryParameters: {'q': v.trim()});
                    if (!mounted) return;
                    setState(() {
                      _photos = (res.data['data']['items'] as List)
                          .map((e) => Map<String, dynamic>.from(e)).toList();
                    });
                  } catch (_) {}
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Storage Info'),
              onTap: () { Navigator.pop(context); _showStorageInfo(context); },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Contributors'),
              onTap: () { Navigator.pop(context); _showContributors(context); },
            ),
          ],
        ),
      ),
    );
  }

  void _showStorageInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _StorageInfoSheet(stats: _stats ?? {}),
    );
  }

  void _showContributors(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ContributorsSheet(contributors: _contributors),
    );
  }
}

// ── Storage Bar ──────────────────────────────────────────────────

class _StorageBar extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StorageBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = (stats['totalCount'] ?? 0) as int;
    final photos = (stats['photoCount'] ?? 0) as int;
    final videos = (stats['videoCount'] ?? 0) as int;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.photo_library, color: AppColors.blue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$total memories',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
                const SizedBox(height: 2),
                Text('$photos photos · $videos videos',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty Gallery ────────────────────────────────────────────────

class _EmptyGallery extends StatelessWidget {
  final VoidCallback onUpload;
  const _EmptyGallery({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.photo_library_outlined, size: 40, color: AppColors.blue),
            ),
            const SizedBox(height: 20),
            Text('No memories yet', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
            const SizedBox(height: 8),
            Text('Upload photos and videos to\nrelive your trip moments',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context))),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.add_a_photo, size: 18),
              label: const Text('Upload First Memory'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Photo Grid ───────────────────────────────────────────────────

class _PhotoGrid extends StatelessWidget {
  final List<Map<String, dynamic>> photos;
  final bool hasMore;
  final bool loadingMore;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final String tripId;
  const _PhotoGrid({
    required this.photos, required this.hasMore, required this.loadingMore,
    required this.onRefresh, required this.onLoadMore, required this.tripId,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemCount: photos.length + (hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == photos.length) {
            return Center(
              child: loadingMore
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : GestureDetector(
                      onTap: onLoadMore,
                      child: Text('Load more', style: TextStyle(color: AppColors.blue, fontSize: 13)),
                    ),
            );
          }
          final p = photos[i];
          final url = (p['thumbnailUrl'] ?? p['cloudinaryUrl'] ?? '').toString();
          final name = ((p['user']?['name'] ?? '').toString()).trim();
          return GestureDetector(
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PhotoDetailScreen(itemId: '${p['id']}', tripId: tripId)));
              onRefresh();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url.isNotEmpty)
                    Image.network(url, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.inputFill(context),
                          child: Icon(Icons.broken_image, color: AppColors.textSecondary(context)),
                        ))
                  else
                    Container(color: AppColors.inputFill(context),
                        child: Icon(Icons.image, color: AppColors.textSecondary(context))),
                  if (name.isNotEmpty)
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                          ),
                        ),
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Albums View ──────────────────────────────────────────────────

class _AlbumsView extends StatelessWidget {
  final List<Map<String, dynamic>> albums;
  final String tripId;
  final VoidCallback onRefresh;
  const _AlbumsView({required this.albums, required this.tripId, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return Center(
        child: Text('No albums yet',
            style: TextStyle(color: AppColors.textSecondary(context))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: albums.length,
      itemBuilder: (ctx, i) {
        final a = albums[i];
        final name = (a['name'] ?? 'Album').toString();
        final count = a['count'] ?? 0;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(ctx,
              MaterialPageRoute(builder: (_) => _AlbumPhotosScreen(name: name, tripId: tripId))),
          child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.folder, color: AppColors.blue, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
                    const SizedBox(height: 2),
                    Text('$count photos', style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSecondary(context)),
            ],
          ),
          ),
        );
      },
    );
  }
}

// ── Album Photos Screen ────────────────────────────────────────────

class _AlbumPhotosScreen extends ConsumerStatefulWidget {
  final String name;
  final String tripId;
  const _AlbumPhotosScreen({required this.name, required this.tripId});

  @override
  ConsumerState<_AlbumPhotosScreen> createState() => _AlbumPhotosScreenState();
}

class _AlbumPhotosScreenState extends ConsumerState<_AlbumPhotosScreen> {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.get('/api/trips/${widget.tripId}/gallery',
          queryParameters: {'album': widget.name, 'size': 100});
      if (!mounted) return;
      setState(() {
        _photos = ((res.data['data']['items'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: Text(widget.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? Center(
                  child: Text('No photos in this album',
                      style: TextStyle(color: AppColors.textSecondary(context))))
              : _PhotoGrid(
                  photos: _photos,
                  hasMore: false,
                  loadingMore: false,
                  onRefresh: _load,
                  onLoadMore: () {},
                  tripId: widget.tripId,
                ),
    );
  }
}

// ── Contributors Row ─────────────────────────────────────────────

class _ContributorsRow extends StatelessWidget {
  final List<Map<String, dynamic>> contributors;
  const _ContributorsRow({required this.contributors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: contributors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = contributors[i];
          final name = (c['name'] ?? 'User').toString().trim();
          final count = c['photoCount'] ?? 0;
          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
          return Column(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.blue.withValues(alpha: 0.15),
                child: Text(initial, style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const SizedBox(height: 2),
              Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context))),
            ],
          );
        },
      ),
    );
  }
}

// ── Storage Info Sheet ───────────────────────────────────────────

class _StorageInfoSheet extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StorageInfoSheet({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = (stats['totalCount'] ?? 0) as int;
    final photos = (stats['photoCount'] ?? 0) as int;
    final videos = (stats['videoCount'] ?? 0) as int;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.cardBorder(context), borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_done, color: AppColors.blue, size: 28),
            ),
            const SizedBox(height: 16),
            Text('Trip Gallery Storage', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.textPrimary(context))),
            const SizedBox(height: 20),
            _storageRow('Photos', '$photos', AppColors.blue),
            const SizedBox(height: 8),
            _storageRow('Videos', '$videos', Colors.teal),
            const SizedBox(height: 8),
            _storageRow('Total', '$total items', AppColors.textSecondary(context)),
            const SizedBox(height: 20),
            Text('Photos uploaded securely · Powered by Cloud Storage',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
          ],
        ),
      ),
    );
  }

  Widget _storageRow(String label, String value, Color color) {
    return Row(
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ── Contributors Sheet ───────────────────────────────────────────

class _ContributorsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> contributors;
  const _ContributorsSheet({required this.contributors});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.cardBorder(context), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Text('Trip Memories Contributors',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary(context))),
          const SizedBox(height: 16),
          ...contributors.map((c) {
            final name = (c['name'] ?? 'User').toString().trim();
            final count = c['photoCount'] ?? 0;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.blue.withValues(alpha: 0.15),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700)),
              ),
              title: Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary(context))),
              trailing: Text('$count photos',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context))),
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
