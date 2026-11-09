import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/auto_refresh.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';
import '../widgets/add_listing_button.dart';
import '../widgets/listing_card.dart';

class VendorListingsPage extends StatefulWidget {
  const VendorListingsPage({super.key});

  @override
  State<VendorListingsPage> createState() => _VendorListingsPageState();
}

class _VendorListingsPageState extends State<VendorListingsPage>
    with AutoRefresh {
  static const double _cardHeight = 250;

  List<Listing>? _listings;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Future<void> autoRefresh() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _listings = null;
        _error = null;
      });
    }
    try {
      final listings = await context.read<ListingRepository>().fetchMine();
      if (mounted) {
        setState(() {
          _listings = listings;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_listings == null) {
        setState(() => _error = e.message);
      } else if (!silent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Widget _scrollable(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    ),
  );

  Future<void> _addListing() async {
    final created = await context.push<Listing>(AppRoutes.vendorAddListing);
    if (created != null && mounted) {
      setState(() => _listings = [created, ...?_listings]);
    }
  }

  Widget _body(BuildContext context) {
    if (_error != null) {
      return _scrollable(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final listings = _listings;
    if (listings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (listings.isEmpty) {
      return _scrollable(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fastfood_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No listings yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text('Add your surplus food so customers can find it.'),
          ],
        ),
      );
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: _cardHeight,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
      ),
      itemCount: listings.length,
      itemBuilder: (context, index) => ListingCard(listing: listings[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'All Listings',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                AddListingButton(onPressed: _addListing),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(silent: true),
                child: _body(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
