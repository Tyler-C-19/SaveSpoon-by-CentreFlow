import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// Icons grow as much as the body text does, so they keep pace with large font
// sizes. They never shrink below their normal size.
double iconScale(BuildContext context) =>
    math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
