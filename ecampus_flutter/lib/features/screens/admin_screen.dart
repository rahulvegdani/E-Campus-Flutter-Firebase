import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Administrator tools')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ref.read(firestoreProvider).collection('authorized_users').orderBy('name').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('Authorized user records could not be loaded.'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            return ListView(padding: const EdgeInsets.all(16), children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${snapshot.data!.docs.length} authorized users', style: const TextStyle(fontWeight: FontWeight.w700)),
                FilledButton.icon(onPressed: () => _addUser(context, ref), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add')),
              ]),
              const SizedBox(height: 16),
              ...snapshot.data!.docs.map((doc) {
                final data = doc.data();
                final active = data['active'] as bool? ?? false;
                return Card(margin: const EdgeInsets.only(bottom: 10), child: SwitchListTile(value: active, onChanged: (value) => ref.read(firestoreProvider).collection('authorized_users').doc(doc.id).update({'active': value, 'updatedAt': FieldValue.serverTimestamp()}), title: Text(data['name'] as String? ?? doc.id, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${data['role'] ?? 'student'} · ${doc.id}'), secondary: Icon(active ? Icons.verified_outlined : Icons.pause_circle_outline, color: active ? AppColors.success : AppColors.warning)));
              }),
            ]);
          },
        ),
      );

  Future<void> _addUser(BuildContext context, WidgetRef ref) async {
    final phone = TextEditingController();
    final name = TextEditingController();
    String role = 'student';
    await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('Authorize account'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'E.164 phone number')), TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')), DropdownButtonFormField<String>(value: role, items: const [DropdownMenuItem(value: 'student', child: Text('Student')), DropdownMenuItem(value: 'teacher', child: Text('Teacher')), DropdownMenuItem(value: 'admin', child: Text('Administrator'))], onChanged: (value) => setDialog(() => role = value ?? role), decoration: const InputDecoration(labelText: 'Role'))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () async { if (phone.text.trim().isEmpty || name.text.trim().isEmpty) return; await ref.read(firestoreProvider).collection('authorized_users').doc(phone.text.trim()).set({'phone': phone.text.trim(), 'name': name.text.trim(), 'role': role, 'active': true, 'department': '', 'semester': '', 'division': '', 'createdAt': FieldValue.serverTimestamp()}); if (context.mounted) Navigator.pop(context); }, child: const Text('Authorize'))]));
    phone.dispose();
    name.dispose();
  }
}