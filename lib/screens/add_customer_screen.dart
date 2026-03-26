import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/delivery_slot.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  DeliverySlot _slot = DeliverySlot.morning;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final repo = context.read<AppRepository>();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    repo.addCustomer(
      Customer(
        id: id,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        preferredSlot: _slot,
        notes: _notes.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add customer'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter a name';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter a phone number';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Delivery address',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter an address';
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Preferred slot',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<DeliverySlot>(
              segments: const [
                ButtonSegment(
                  value: DeliverySlot.morning,
                  label: Text('Morning'),
                  icon: Icon(Icons.wb_sunny_outlined),
                ),
                ButtonSegment(
                  value: DeliverySlot.evening,
                  label: Text('Evening'),
                  icon: Icon(Icons.nights_stay_outlined),
                ),
              ],
              selected: {_slot},
              onSelectionChanged: (s) {
                setState(() => _slot = s.first);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Save customer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
