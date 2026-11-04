import 'package:flutter/material.dart';

abstract final class BrandHeader {
  static const double height = 210;
  static const String logoAsset = 'assets/images/logo.png';

  static Widget logo({Key? key}) => Image.asset(
    logoAsset,
    key: key,
    width: height,
    height: height,
    cacheWidth: 840,
    semanticLabel: 'SaveSpoon',
  );

  static double logoCentreY(BuildContext context) =>
      MediaQuery.paddingOf(context).top + height / 2;
}
