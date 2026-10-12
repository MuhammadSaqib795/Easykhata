import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Result of picking a person from the phone's address book.
class PickedContact {
  const PickedContact({required this.name, required this.phone});
  final String name;
  final String phone;
}

/// Cleans a phone number: keeps digits and a single leading '+'.
String cleanPhone(String raw) {
  final trimmed = raw.trim();
  final hasPlus = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  return hasPlus ? '+$digits' : digits;
}

/// Returns an error message, or null when the number is acceptable.
/// Rule: at least 11 digits (a leading '+' is not counted), max 15.
String? validatePhone(String? value) {
  final v = cleanPhone(value ?? '');
  if (v.isEmpty) return 'Enter a phone number';
  final digitCount = v.replaceAll('+', '').length;
  if (digitCount < 11) return 'Phone number must be at least 11 digits';
  if (digitCount > 15) return 'Phone number is too long';
  return null;
}

/// Opens a searchable list of phone contacts. Returns null if the user
/// cancels or denies permission ([onError] is called with a message so the
/// caller can tell the user to type the number manually).
Future<PickedContact?> pickPhoneContact(
  BuildContext context, {
  required void Function(String message) onError,
}) async {
  List<Contact> contacts;
  try {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      onError('Contacts permission denied. You can type the number manually.');
      return null;
    }
    if (!context.mounted) return null;
    // Reading a large address book takes a moment: show that it is working.
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(width: 18),
              Text('Loading contacts…'),
            ],
          ),
        ),
      ),
    );
    try {
      contacts = await FlutterContacts.getContacts(withProperties: true);
    } finally {
      navigator.pop();
    }
  } catch (e) {
    onError('Could not read contacts. You can type the number manually.');
    return null;
  }

  contacts = contacts.where((c) => c.phones.isNotEmpty).toList()
    ..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

  if (contacts.isEmpty) {
    onError('No contacts with phone numbers found. Type the number manually.');
    return null;
  }
  if (!context.mounted) return null;

  final chosen = await showModalBottomSheet<Contact>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ContactListSheet(contacts: contacts),
  );
  if (chosen == null || !context.mounted) return null;

  // Contacts can have several numbers -> let the user choose one.
  String? number;
  if (chosen.phones.length == 1) {
    number = chosen.phones.first.number;
  } else {
    number = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(chosen.displayName),
        children: [
          for (final p in chosen.phones)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.number),
              child: Text(p.number),
            ),
        ],
      ),
    );
  }
  if (number == null) return null;

  return PickedContact(name: chosen.displayName, phone: cleanPhone(number));
}

class _ContactListSheet extends StatefulWidget {
  const _ContactListSheet({required this.contacts});
  final List<Contact> contacts;

  @override
  State<_ContactListSheet> createState() => _ContactListSheetState();
}

class _ContactListSheetState extends State<_ContactListSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = widget.contacts.where((c) {
      if (q.isEmpty) return true;
      return c.displayName.toLowerCase().contains(q) ||
          c.phones.any((p) => p.number.replaceAll(' ', '').contains(q));
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Text(
                'Select Contact',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Search name or number',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching contacts'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                c.displayName.isEmpty
                                    ? '?'
                                    : c.displayName[0].toUpperCase(),
                              ),
                            ),
                            title: Text(c.displayName),
                            subtitle: Text(c.phones.first.number),
                            onTap: () => Navigator.pop(context, c),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
