import '../../auth/domain/auth_user.dart';
import '../../seller_profile/domain/vendor_profile.dart';
import 'photo_crop.dart';

class UserProfile {
  const UserProfile({
    required this.user,
    this.photoUrl,
    this.photoOriginalUrl,
    this.photoCrop,
    this.hasPassword = true,
    this.isGoogleLinked = false,
    this.lockedUntil,
    this.vendor,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final vendor = json['vendor'];
    return UserProfile(
      user: AuthUser.fromJson(json),
      photoUrl: json['photoUrl'] as String?,
      photoOriginalUrl: json['photoOriginalUrl'] as String?,
      photoCrop: PhotoCrop.fromJson(json['photoCrop']),
      hasPassword: json['hasPassword'] as bool? ?? true,
      isGoogleLinked: json['isGoogleLinked'] as bool? ?? false,
      lockedUntil: DateTime.tryParse(json['lockedUntil'] as String? ?? ''),
      vendor: vendor is Map<String, dynamic>
          ? VendorProfile.fromJson(vendor)
          : null,
    );
  }

  final AuthUser user;
  final String? photoUrl;

  // The uploaded picture before framing. Missing for older pictures.
  final String? photoOriginalUrl;
  final PhotoCrop? photoCrop;
  final bool hasPassword;
  final bool isGoogleLinked;

  // Set while too many wrong password tries block password actions.
  final DateTime? lockedUntil;
  final VendorProfile? vendor;

  bool get canChangeEmail => hasPassword && !isGoogleLinked;

  bool get canReframePhoto => photoUrl != null && photoOriginalUrl != null;

  bool isLocked([DateTime? now]) =>
      lockedUntil != null && lockedUntil!.isAfter(now ?? DateTime.now());

  // Whole minutes left, rounded up, at least 1.
  int lockMinutesLeft([DateTime? now]) {
    final left = lockedUntil!.difference(now ?? DateTime.now());
    return (left.inSeconds / 60).ceil().clamp(1, 1 << 30);
  }

  String get lockMessage {
    final minutes = lockMinutesLeft();
    return 'Locked for $minutes minute${minutes == 1 ? '' : 's'} after too '
        'many wrong password tries.';
  }
}

// What an edit page closes with: the banner text and the saved profile, so
// the profile page can show it before the page has finished closing.
class ProfileChange {
  const ProfileChange(this.message, this.profile);

  final String message;
  final UserProfile? profile;
}

class AccountSummary {
  const AccountSummary({
    required this.listingCount,
    required this.activeListingCount,
    required this.activeOrderCount,
  });

  factory AccountSummary.fromJson(Map<String, dynamic> json) => AccountSummary(
    listingCount: json['listingCount'] as int? ?? 0,
    activeListingCount: json['activeListingCount'] as int? ?? 0,
    activeOrderCount: json['activeOrderCount'] as int? ?? 0,
  );

  final int listingCount;
  final int activeListingCount;
  final int activeOrderCount;

  bool get blocksDeletion => activeListingCount > 0 || activeOrderCount > 0;

  // Matches the server's message.
  String get blockedMessage {
    String count(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    final parts = [
      if (activeListingCount > 0) count(activeListingCount, 'active listing'),
      if (activeOrderCount > 0) count(activeOrderCount, 'active order'),
    ];
    return 'You have ${parts.join(' and ')}. You can delete your account '
        'once pickup has ended for all of them.';
  }
}
