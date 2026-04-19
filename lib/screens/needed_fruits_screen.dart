import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/needed_fruit.dart';
import '../utils/needed_fruit_weight_parse.dart';

/// Dialog-owned controllers; disposed only after the route is fully removed.
class _NeededFruitEditorDialog extends StatefulWidget {
  const _NeededFruitEditorDialog({this.existing});

  final NeededFruit? existing;

  @override
  State<_NeededFruitEditorDialog> createState() =>
      _NeededFruitEditorDialogState();
}

class _NeededFruitEditorDialogState extends State<_NeededFruitEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  late final FocusNode _nameFocus;
  late final FocusNode _qtyFocus;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.fruitName ?? '');
    _qtyCtrl = TextEditingController(text: e?.quantityNotes ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _nameFocus = FocusNode();
    _qtyFocus = FocusNode();
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _qtyFocus.dispose();
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(
      context,
      (
        _nameCtrl.text.trim(),
        _qtyCtrl.text.trim(),
        _notesCtrl.text.trim(),
      ),
    );
  }

  static Widget _suggestionOverlay(
    BuildContext context,
    AutocompleteOnSelected<String> onSelected,
    Iterable<String> options,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220, minWidth: 260),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final o = options.elementAt(i);
              return InkWell(
                onTap: () => onSelected(o),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    o,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? 'Add fruit' : 'Edit fruit'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RawAutocomplete<String>(
                textEditingController: _nameCtrl,
                focusNode: _nameFocus,
                displayStringForOption: (s) => s,
                optionsBuilder: (tv) =>
                    repo.suggestedPurchaseFruitNames(tv.text),
                optionsViewBuilder: (context, onSelected, options) =>
                    _suggestionOverlay(context, onSelected, options),
                fieldViewBuilder: (context, textController, focusNode, submit) {
                  return TextFormField(
                    controller: textController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Fruit name',
                      helperText: 'Suggestions from past list & purchases',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                    onFieldSubmitted: (_) => submit(),
                  );
                },
                onSelected: (_) {},
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _nameCtrl,
                builder: (context, _) {
                  return RawAutocomplete<String>(
                    textEditingController: _qtyCtrl,
                    focusNode: _qtyFocus,
                    displayStringForOption: (s) => s,
                    optionsBuilder: (tv) =>
                        repo.suggestedPurchaseQuantityNotes(
                          fruitName: _nameCtrl.text.trim(),
                          prefix: tv.text,
                        ),
                    optionsViewBuilder: (context, onSelected, options) =>
                        _suggestionOverlay(context, onSelected, options),
                    fieldViewBuilder:
                        (context, textController, focusNode, submit) {
                      return TextFormField(
                        controller: textController,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Quantity to buy',
                          hintText: 'e.g. 5 kg, 2 crates',
                          helperText: _nameCtrl.text.trim().isEmpty
                              ? 'Suggestions from all past quantities'
                              : 'Quantities used before for this fruit name',
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                        onFieldSubmitted: (_) => submit(),
                      );
                    },
                    onSelected: (_) {},
                  );
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Returns `(pricePerKgRupees?, totalWeightKg, totalCostRupees)`.
class _BuyNeededFruitDialog extends StatefulWidget {
  const _BuyNeededFruitDialog({required this.item});

  final NeededFruit item;

  @override
  State<_BuyNeededFruitDialog> createState() => _BuyNeededFruitDialogState();
}

class _BuyNeededFruitDialogState extends State<_BuyNeededFruitDialog> {
  late final TextEditingController _perKgCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _totalCtrl;
  String? _error;

  static double? _parse(String s) {
    final t = s.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  @override
  void initState() {
    super.initState();
    final guess = guessWeightKgFromQuantityNotes(widget.item.quantityNotes);
    _perKgCtrl = TextEditingController();
    _weightCtrl = TextEditingController(
      text: guess != null ? guess.toString() : '',
    );
    _totalCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _perKgCtrl.dispose();
    _weightCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  void _applySuggestedTotal() {
    final pk = _parse(_perKgCtrl.text);
    final w = _parse(_weightCtrl.text);
    if (pk != null && pk > 0 && w != null && w > 0) {
      final v = double.parse((pk * w).toStringAsFixed(2));
      _totalCtrl.text = v == v.roundToDouble() ? '${v.round()}' : '$v';
      setState(() => _error = null);
    }
  }

  void _submit() {
    final w = _parse(_weightCtrl.text);
    final pk = _parse(_perKgCtrl.text);
    final totalRaw = _totalCtrl.text.trim();
    final totalParsed = totalRaw.isEmpty ? null : _parse(totalRaw);

    if (totalRaw.isNotEmpty && totalParsed == null) {
      setState(() => _error = 'Total cost must be a valid number.');
      return;
    }

    if (w == null || w <= 0) {
      setState(() => _error = 'Enter total weight (kg), greater than 0.');
      return;
    }

    double totalCost;
    if (totalParsed != null && totalParsed >= 0) {
      totalCost = totalParsed;
    } else if (pk != null && pk > 0) {
      totalCost = double.parse((pk * w).toStringAsFixed(2));
    } else {
      setState(
        () => _error =
            'Enter total cost (₹), or fill price/kg and use suggested total.',
      );
      return;
    }

    Navigator.pop(context, (pk, w, totalCost));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.item;
    final pk = _parse(_perKgCtrl.text);
    final w = _parse(_weightCtrl.text);
    final suggested = (pk != null &&
            pk > 0 &&
            w != null &&
            w > 0)
        ? double.parse((pk * w).toStringAsFixed(2))
        : null;

    return AlertDialog(
      title: const Text('Mark as bought'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              f.fruitName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              f.quantityNotes.isEmpty ? '—' : f.quantityNotes,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _perKgCtrl,
              decoration: const InputDecoration(
                labelText: 'Price per kg (₹)',
                hintText: 'Optional if you enter total',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weightCtrl,
              decoration: const InputDecoration(
                labelText: 'Total weight (kg)',
                helperText: 'Prefilled from quantity when possible; you can edit',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _totalCtrl,
              decoration: const InputDecoration(
                labelText: 'Total cost (₹)',
                hintText: 'Optional if price/kg × weight applies',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() => _error = null),
            ),
            if (suggested != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _applySuggestedTotal,
                  icon: const Icon(Icons.calculate_outlined, size: 20),
                  label: Text(
                    'Use suggested total: ₹$suggested',
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Bought'),
        ),
      ],
    );
  }
}

class NeededFruitsScreen extends StatelessWidget {
  const NeededFruitsScreen({super.key});

  Future<void> _showEditor(
    BuildContext context, {
    NeededFruit? existing,
  }) async {
    final repo = context.read<AppRepository>();
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (ctx) => _NeededFruitEditorDialog(existing: existing),
    );
    if (result == null || !context.mounted) return;
    final (name, qty, notes) = result;
    try {
      if (existing == null) {
        await repo.addNeededFruit(
          fruitName: name,
          quantityNotes: qty,
          notes: notes,
        );
      } else {
        await repo.updateNeededFruit(
          existing.id,
          fruitName: name,
          quantityNotes: qty,
          notes: notes,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save. Check connection or Firestore rules.'),
        ),
      );
    }
  }

  Future<void> _showBuy(BuildContext context, NeededFruit item) async {
    if (item.purchased) return;
    final repo = context.read<AppRepository>();
    final result = await showDialog<(double?, double, double)>(
      context: context,
      builder: (ctx) => _BuyNeededFruitDialog(item: item),
    );
    if (result == null || !context.mounted) return;
    final (pricePerKg, weightKg, totalCost) = result;
    try {
      await repo.recordNeededFruitPurchase(
        id: item.id,
        totalWeightKg: weightKg,
        pricePerKgRupees: pricePerKg,
        totalCostRupees: totalCost,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save purchase. Check connection or rules.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final items = repo.neededFruits;
    final pending = items.where((e) => !e.purchased).toList();
    final bought = items.where((e) => e.purchased).toList();
    final cs = Theme.of(context).colorScheme;
    final canEdit = repo.isAdmin || repo.isFruitBuyer;
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final currencyInt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final df = DateFormat.yMMMd().add_jm();

    String formatCost(double? v) {
      if (v == null) return '—';
      final x = v.roundToDouble() == v;
      return x ? currencyInt.format(v) : currency.format(v);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fruit purchase list'),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: () => _showEditor(context),
              tooltip: 'Add',
              child: const Icon(Icons.add),
            )
          : null,
      body: repo.neededFruitsLoading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Text(
                    canEdit
                        ? 'Nothing to buy yet. Tap + to add a fruit.'
                        : 'No items on the list.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => repo.refreshNeededFruits(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      if (pending.isNotEmpty) ...[
                        Text(
                          'To buy',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        for (final f in pending) ...[
                          Card(
                            child: ListTile(
                              title: Text(
                                f.fruitName.isEmpty ? '—' : f.fruitName,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    f.quantityNotes.isEmpty
                                        ? '—'
                                        : f.quantityNotes,
                                  ),
                                  if (f.notes.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      f.notes,
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: canEdit
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FilledButton.tonal(
                                          onPressed: () => _showBuy(context, f),
                                          child: const Text('Buy'),
                                        ),
                                        IconButton(
                                          tooltip: 'Edit',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () =>
                                              _showEditor(context, existing: f),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ] else if (bought.isNotEmpty) ...[
                        Text(
                          'Nothing left to buy',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (bought.isNotEmpty) ...[
                        Text(
                          'Bought',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        for (final f in bought) ...[
                          Card(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.35,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          f.fruitName.isEmpty ? '—' : f.fruitName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: const Text('Bought'),
                                        avatar: Icon(
                                          Icons.check_circle_outline,
                                          size: 18,
                                          color: cs.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (f.purchasedAt != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      df.format(f.purchasedAt!.toLocal()),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    '${f.quantityNotes.isEmpty ? '—' : f.quantityNotes}'
                                    '${f.totalWeightKg != null ? ' · ${f.totalWeightKg} kg weighed' : ''}',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Total: ${formatCost(f.totalCostRupees)}'
                                    '${f.pricePerKgRupees != null && f.pricePerKgRupees! > 0 ? ' · ${formatCost(f.pricePerKgRupees)}/kg' : ''}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }
}
