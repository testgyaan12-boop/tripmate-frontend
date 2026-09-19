import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/storage/token_storage.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../core/data/refresh.dart';

/// WhatsApp-inspired group chat: text, image sharing, location sharing.
/// Live via STOMP, REST fallback for sends.
class ChatScreen extends ConsumerStatefulWidget {
  final String tripId;
  const ChatScreen({super.key, required this.tripId});

  @override
  ConsumerState<ChatScreen> createState() => _State();
}

class _State extends ConsumerState<ChatScreen> {
  List<Map<String, dynamic>> _msgs = [];
  Map<int, Map<String, dynamic>> _profiles = {};
  Map<String, dynamic>? _trip;
  int? _me;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  StompClient? _stomp;
  bool _sending = false;

  static const _avatarColors = [
    Color(0xFF2563EB),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF10B981),
  ];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void didUpdateWidget(covariant ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.tripId != widget.tripId) _boot();
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _stomp?.deactivate();
    super.dispose();
  }

  Future<void> _boot() async {
    await _history();
    _connect();
  }

  Future<void> _history() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get('/api/trips/${widget.tripId}/chat/messages'),
        dio.get('/api/trips/${widget.tripId}/members/detailed'),
        dio.get('/api/trips/${widget.tripId}'),
        dio.get('/api/users/me'),
      ]);
      if (!mounted) return;
      final profiles = <int, Map<String, dynamic>>{};
      for (final e in (res[1].data['data'] as List)) {
        final m = Map<String, dynamic>.from(e);
        profiles[(m['userId'] as num).toInt()] = m;
      }
      setState(() {
        _msgs = ((res[0].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _profiles = profiles;
        _trip =
            Map<String, dynamic>.from(res[2].data['data'] as Map);
        _me = (res[3].data['data']['id'] as num?)?.toInt();
      });
      _toBottom();
    } catch (_) {}
  }

  Future<void> _connect() async {
    final token = await TokenStorage().access();
    _stomp = StompClient(
      config: StompConfig.sockJS(
        url: ApiConstants.wsUrl,
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        onConnect: (f) {
          _stomp?.subscribe(
            destination: '/topic/trip.${widget.tripId}',
            callback: (_) => _history(),
          );
        },
      ),
    );
    _stomp?.activate();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send({
    String? content,
    String? imageUrl,
    double? lat,
    double? lng,
  }) async {
    if ((content == null || content.trim().isEmpty) &&
        imageUrl == null &&
        lat == null) {
      return;
    }
    setState(() => _sending = true);
    try {
      final payload = <String, dynamic>{'senderId': _me};
      if (content != null) payload['content'] = content.trim();
      if (imageUrl != null) payload['imageUrl'] = imageUrl;
      if (lat != null) payload['sharedLat'] = lat;
      if (lng != null) payload['sharedLng'] = lng;
      final body = jsonEncode(payload);
      var sent = false;
      try {
        if (_me != null) {
          _stomp?.send(
            destination: '/app/trip.${widget.tripId}.send',
            body: body,
          );
          sent = true;
        }
      } catch (_) {}
      if (!sent) {
        final dio = ref.read(dioClientProvider).dio;
        final data = <String, dynamic>{};
        if (content != null) data['content'] = content.trim();
        if (imageUrl != null) data['imageUrl'] = imageUrl;
        if (lat != null) data['sharedLat'] = lat;
        if (lng != null) data['sharedLng'] = lng;
        await dio.post(
          '/api/trips/${widget.tripId}/chat/messages',
          data: data,
        );
      }
      bumpData(ref);
      _text.clear();
      await Future.delayed(const Duration(milliseconds: 400));
      _history();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (file == null) return;
      setState(() => _sending = true);
      final dio = ref.read(dioClientProvider).dio;
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path,
            filename: file.name),
      });
      final res = await dio.post('/api/files/upload', data: form);
      var url = res.data['data']['url'].toString();
      if (url.startsWith('/')) url = ApiConstants.baseUrl + url;
      setState(() => _sending = false);
      _send(imageUrl: url);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  void _imageSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }
      final pos = await Geolocator.getCurrentPosition();
      _send(lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  String _time(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  String _fullImage(String url) =>
      url.startsWith('/') ? ApiConstants.baseUrl + url : url;

  @override
  Widget build(BuildContext context) {
    ref.listen(dataVersionProvider, (_, _) => _history());
    final tripName =
        (_trip?['tripName'] ?? 'Trip').toString();
    return Scaffold(
      backgroundColor: const Color(0xFFEFE7DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/trips/${widget.tripId}/map'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _history,
          ),
        ],
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.route,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$tripName Group',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${_profiles.length} members',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xD9FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet. Say hello! 👋',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding:
                        const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m = _msgs[i];
                      final sid =
                          (m['senderId'] as num?)?.toInt() ?? -1;
                      return _Bubble(
                        mine: sid == _me,
                        profile: _profiles[sid],
                        senderId: sid,
                        content: m['content']?.toString(),
                        imageUrl: m['imageUrl']?.toString(),
                        lat: (m['sharedLat'] as num?)?.toDouble(),
                        lng: (m['sharedLng'] as num?)?.toDouble(),
                        time: _time(m['createdAt']?.toString()),
                        fullImage: _fullImage,
                        onLocation: () => context
                            .go('/trips/${widget.tripId}/map'),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: const Color(0xFFF0F0F0),
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                top: 8,
                bottom:
                    MediaQuery.of(context).viewInsets.bottom + 8,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_camera_outlined,
                        color: Color(0xFF64748B)),
                    onPressed: _sending ? null : _imageSheet,
                    tooltip: 'Share photo',
                  ),
                  IconButton(
                    icon: const Icon(Icons.location_on_outlined,
                        color: Color(0xFF64748B)),
                    onPressed: _sending ? null : _shareLocation,
                    tooltip: 'Share location',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) =>
                          _send(content: _text.text),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                        backgroundColor:
                            const Color(0xFF2563EB),
                      ),
                      onPressed: _sending
                          ? null
                          : () => _send(content: _text.text),
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.send, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool mine;
  final Map<String, dynamic>? profile;
  final int senderId;
  final String? content;
  final String? imageUrl;
  final double? lat;
  final double? lng;
  final String time;
  final String Function(String) fullImage;
  final VoidCallback onLocation;

  const _Bubble({
    required this.mine,
    required this.profile,
    required this.senderId,
    required this.content,
    required this.imageUrl,
    required this.lat,
    required this.lng,
    required this.time,
    required this.fullImage,
    required this.onLocation,
  });

  @override
  Widget build(BuildContext context) {
    final name = (profile?['name']?.toString() ?? '').isNotEmpty
        ? profile!['name'].toString()
        : 'Traveller $senderId';
    final img = profile?['profileImage'] as String?;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFFD9FDD3) : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(mine ? 14 : 4),
          bottomRight: Radius.circular(mine ? 4 : 14),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 3),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _State
                      ._avatarColors[senderId.abs() %
                          _State._avatarColors.length],
                ),
              ),
            ),
          if (imageUrl != null && imageUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  fullImage(imageUrl!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 120,
                    color: const Color(0xFFE2E8F0),
                    child: const Center(
                        child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            ),
          if (lat != null && lng != null)
            InkWell(
              onTap: onLocation,
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on,
                        color: Color(0xFF2563EB)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Shared location',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                          Text(
                            '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const Text(
                            'Tap to view on map',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (content != null && content!.isNotEmpty)
            Text(
              content!,
              style: const TextStyle(fontSize: 15, height: 1.35),
            ),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF8696A0),
              ),
            ),
          ),
        ],
      ),
    );
    if (mine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [bubble],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: _State._avatarColors[
                senderId.abs() % _State._avatarColors.length],
            backgroundImage:
                img != null ? NetworkImage(img) : null,
            child: img == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          bubble,
        ],
      ),
    );
  }
}
