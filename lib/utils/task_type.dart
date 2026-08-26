// Single source of truth for maintenance task type labels. Previously this
// same code/label mapping was copy-pasted separately in 4 different files —
// changing or adding a task type meant remembering to update all 4. Now
// there's just this one file to touch.

/// Short circular-badge code: PM, BM, CL, AD, CO, TR, OT.
String taskTypeCode(String type) {
  switch (type) {
    case 'preventive':
      return 'PM';
    case 'breakdown':
      return 'BM';
    case 'calibration':
      return 'CL';
    case 'adjustment':
      return 'AD';
    case 'changeover':
      return 'CO';
    case 'trial':
      return 'TR';
    case 'others':
      return 'OT';
    default:
      return type.toUpperCase();
  }
}

/// Full word: Preventive, Breakdown, Calibration, Adjustment, Changeover,
/// Trial, Others.
String taskTypeName(String type) {
  switch (type) {
    case 'preventive':
      return 'Preventive';
    case 'breakdown':
      return 'Breakdown';
    case 'calibration':
      return 'Calibration';
    case 'adjustment':
      return 'Adjustment';
    case 'changeover':
      return 'Changeover';
    case 'trial':
      return 'Trial';
    case 'others':
      return 'Others';
    default:
      return type;
  }
}

/// All type keys, in the order they should appear as selectable options.
const List<String> allTaskTypes = [
  'preventive',
  'breakdown',
  'calibration',
  'adjustment',
  'changeover',
  'trial',
  'others',
];

/// Combined "PM · Preventive" style label, used where the technician picks
/// a task type and needs to see the full word, not just the code.
String taskTypeCodeAndName(String type) =>
    '${taskTypeCode(type)} · ${taskTypeName(type)}';
