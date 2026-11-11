import '../../../core/network/api_client.dart';
import '../domain/photo_crop.dart';
import '../domain/user_profile.dart';

class ProfileRepository {
  ProfileRepository(this.api);

  final ApiClient api;

  static UserProfile _profile(dynamic data) {
    final user = data is Map ? data['user'] : null;
    if (user is! Map<String, dynamic>) {
      throw const ApiException("We couldn't load your profile.");
    }
    return UserProfile.fromJson(user);
  }

  Future<UserProfile> fetch() async => _profile(await api.get('/api/users/me'));

  Future<UserProfile> updateDetails({
    required String name,
    required String phone,
  }) async => _profile(
    await api.patch('/api/users/me', body: {'name': name, 'phone': phone}),
  );

  // Returns the new token for this phone.
  Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final data = await api.post(
      '/api/users/me/password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    return data['token'] as String;
  }

  Future<void> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) => api.post(
    '/api/users/me/email',
    body: {'newEmail': newEmail, 'currentPassword': currentPassword},
  );

  Future<void> resendEmailChange() => api.post('/api/users/me/email/resend');

  Future<void> cancelEmailChange() => api.delete('/api/users/me/email');

  Future<UserProfile> verifyEmailChange(String code) async => _profile(
    await api.post('/api/users/me/email/verify', body: {'code': code}),
  );

  Future<UserProfile> uploadPhoto(
    List<int> bytes,
    String filename,
    PhotoCrop crop,
  ) async => _profile(
    await api.putFile(
      '/api/users/me/photo',
      field: 'photo',
      bytes: bytes,
      filename: filename,
      fields: crop.toFormFields(),
    ),
  );

  Future<UserProfile> reframePhoto(PhotoCrop crop) async => _profile(
    await api.patch('/api/users/me/photo', body: {'crop': crop.toJson()}),
  );

  Future<UserProfile> removePhoto() async =>
      _profile(await api.delete('/api/users/me/photo'));

  Future<AccountSummary> summary() async => AccountSummary.fromJson(
    await api.get('/api/users/me/summary') as Map<String, dynamic>,
  );

  Future<void> deleteAccount({String? password, String? confirm}) => api.delete(
    '/api/users/me',
    body: {'password': ?password, 'confirm': ?confirm},
  );
}
