import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../domain/search_filters.dart';

// Opens Search from elsewhere showing only these filters, such as View All
// under Your Favourites. Search takes them when it next shows.
abstract final class SearchShortcut {
  static final ValueNotifier<SearchFilters?> filters = ValueNotifier(null);

  static void open(BuildContext context, SearchFilters next) {
    filters.value = next;
    context.go(AppRoutes.customerSearch);
  }
}
