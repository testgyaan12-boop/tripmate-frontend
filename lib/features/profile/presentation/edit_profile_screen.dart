import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/api_error.dart';
import '../data/profile_repository.dart';
import 'widgets/profile_widgets.dart';

const _styles = ['Explorer', 'Adventure', 'Relaxed', 'Luxury', 'Budget'];
const _vehicles = ['Car', 'Bike', 'SUV', 'Campervan', 'Bus', 'Train'];
const _budgets = ['Low', 'Medium', 'High'];

/// Edit Profile: photo (upload), name, email, mobile, city + preferences.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _State();
}

class _State extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _city = TextEditingController();
  final _favs = TextEditingController();
  String? _style;
  String? _vehicle;
  String? _budget;
  String? _photo;
  bool _loaded = false;
  bool _busy = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _mobile.dispose();
    _city.dispose();
    _favs.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    try {
      final u = await ref.read(profileRepositoryProvider).me();
      if (!mounted) return;
      setState(() {
        _name.text = (u['name'] ?? '').toString();
        _email.text = (u['email'] ?? '').toString();
        _mobile.text = (u['mobile'] ?? '').toString();
        _city.text = (u['city'] ?? '').toString();
        _favs.text = (u['favoritePlaces'] ?? '').toString();
        _style = _styles.contains(u['travelStyle']) ? u['travelStyle'] : null;
        _vehicle = _vehicles.contains(u['vehicle']) ? u['vehicle'] : null;
        _budget = _budgets.contains(u['budgetType']) ? u['budgetType'] : null;
        _photo = u['profileImage'] as String?;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 80,
      );
      if (file == null) return;
      setState(() => _uploading = true);
      final url = await ref
          .read(profileRepositoryProvider)
          .uploadAvatar(file.path, file.name);
      if (!mounted) return;
      setState(() {
        _photo = url;
        _uploading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).update({
        'name': _name.text.trim(),
        'mobile': _mobile.text.trim(),
        'city': _city.text.trim(),
        'profileImage': _photo,
        'travelStyle': _style,
        'favoritePlaces': _favs.text.trim(),
        'vehicle': _vehicle,
        'budgetType': _budget,
      });
      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved')),
        );
        context.go('/profile');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/profile'),
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 48,
                                backgroundColor:
                                    const Color(0xFFEFF6FF),
                                backgroundImage: _photo != null
                                    ? NetworkImage(_photo!)
                                    : null,
                                child: _photo == null
                                    ? const Icon(
                                        Icons.person,
                                        size: 48,
                                        color: Color(0xFF2563EB),
                                      )
                                    : null,
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Material(
                                  color: const Color(0xFF2563EB),
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder:
                                        const CircleBorder(),
                                    onTap: _uploading
                                        ? null
                                        : _pickPhoto,
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.all(7),
                                      child: _uploading
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons
                                                  .photo_camera_outlined,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _field(_name, 'Name',
                            validator: (v) =>
                                v == null || v.trim().isEmpty
                                    ? 'Enter your name'
                                    : null),
                        const SizedBox(height: 10),
                        _field(_email, 'Email',
                            keyboard: TextInputType.emailAddress,
                            enabled: false),
                        const SizedBox(height: 10),
                        _field(_mobile, 'Mobile Number',
                            keyboard: TextInputType.phone),
                        const SizedBox(height: 10),
                        _field(_city, 'City (e.g. Mumbai)'),
                        const SectionTitle('Travel Preferences'),
                        _drop('Travel Style', _style, _styles,
                            (v) => setState(() => _style = v),
                            Icons.explore_outlined),
                        const SizedBox(height: 10),
                        _field(_favs,
                            'Favorite Destinations (comma separated)'),
                        const SizedBox(height: 10),
                        _drop('Vehicle Type', _vehicle, _vehicles,
                            (v) => setState(() => _vehicle = v),
                            Icons.directions_car_outlined),
                        const SizedBox(height: 10),
                        _drop('Budget Type', _budget, _budgets,
                            (v) => setState(() => _budget = v),
                            Icons.wallet_outlined),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: _busy ? null : _save,
                            child: Text(
                                _busy ? 'Saving…' : 'Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint, {
    TextInputType keyboard = TextInputType.text,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: keyboard,
      enabled: enabled,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _drop(String hint, String? value, List<String> items,
      void Function(String?) onChanged, IconData icon) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
