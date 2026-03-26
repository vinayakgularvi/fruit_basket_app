import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/delivery_slot.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  DeliverySlot _slot = DeliverySlot.morning;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final list = repo.customersForSlot(_slot);
    final done = repo.completedCountForSlot(_slot);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today’s route'),
        actions: [
          TextButton(
            onPressed: list.isEmpty
                ? null
                : () {
                    repo.markAllDeliveriesDone(_slot, true);
                  },
            child: const Text('Mark all'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'Check off each stop as you complete it.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: SegmentedButton<DeliverySlot>(
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LinearProgressIndicator(
              value: list.isEmpty ? 0 : done / list.length,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              '$done / ${list.length} completed · ${_slot.label}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'No ${_slot.label.toLowerCase()} deliveries today.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final Customer c = list[i];
                      final checked = repo.isDeliveryChecked(c.id);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: CheckboxListTile(
                          value: checked,
                          onChanged: (_) => repo.toggleDeliveryDone(c.id),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            c.name,
                            style: TextStyle(
                              decoration: checked
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: checked
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            '${c.phone}\n${c.address}'
                            '${c.notes.isNotEmpty ? '\n${c.notes}' : ''}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
