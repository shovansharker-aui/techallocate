import 'package:flutter/material.dart';
import '../models/machine.dart';

/// A resolved machine group: [main] is the unit with the lowest
/// equipment id in the group (always treated as the group's "primary"
/// machine everywhere it's displayed), [units] is every machine sharing
/// that group value, [main] included.
class ResolvedGroup {
  final Machine main;
  final List<Machine> units;
  const ResolvedGroup({required this.main, required this.units});
}

/// If [machine] belongs to a group with other members, returns that
/// group resolved (main unit + all units). Returns null if the machine
/// isn't grouped, or is the only machine in its group (nothing to pick
/// between).
ResolvedGroup? resolveGroup(Machine machine, List<Machine> allMachines) {
  if (!machine.isGrouped) return null;
  final units = allMachines.where((m) => m.group.trim().toLowerCase() == machine.group.trim().toLowerCase()).toList()
    ..sort((a, b) => a.equipmentId.compareTo(b.equipmentId));
  if (units.length <= 1) return null;
  return ResolvedGroup(main: units.first, units: units);
}

/// Shows a checklist of every unit in [resolved], pre-checking [tapped],
/// and returns the set of OTHER selected unit ids (main excluded — the
/// main unit is implied separately via WorkOrder.machineId, this return
/// value is exactly what should be shown as "other selected subunits").
/// Returns null if the user cancels.
Future<Set<String>?> pickGroupUnits(BuildContext context, {required Machine tapped, required ResolvedGroup resolved}) async {
  final selected = <String>{tapped.id};
  return showDialog<Set<String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Part of "${resolved.main.group}"'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This machine is part of a group. Select every unit involved in this task:'),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView(
                  shrinkWrap: true,
                  children: resolved.units.map((unit) {
                    return CheckboxListTile(
                      value: selected.contains(unit.id),
                      title: Text(unit.displayName),
                      subtitle: Text(unit.equipmentId + (unit.id == resolved.main.id ? ' · main unit' : '')),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          selected.add(unit.id);
                        } else {
                          selected.remove(unit.id);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, selected..remove(resolved.main.id)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ),
  );
}
