import 'package:firebase_auth/firebase_auth.dart';

class UserFacingError {
  const UserFacingError({required this.message, this.actionHint});

  final String message;
  final String? actionHint;
}

UserFacingError mapToUserFacingError(Object error) {
  if (error is FirebaseAuthException) {
    return _mapAuthError(error);
  }

  if (error is FirebaseException) {
    return _mapFirebaseError(error);
  }

  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (lower.contains('gmail api is not enabled') ||
      lower.contains('accessnotconfigured') ||
      lower.contains('service_disabled')) {
    return const UserFacingError(
      message: 'Gmail API is not enabled for this project.',
      actionHint:
          'Enable Gmail API in Google Cloud Console, then retry in 2-5 minutes.',
    );
  }

  if (lower.contains('network') ||
      lower.contains('socketexception') ||
      lower.contains('unavailable')) {
    return const UserFacingError(
      message: 'Network connection is unavailable.',
      actionHint: 'Check internet and retry.',
    );
  }

  return UserFacingError(
    message: 'Something went wrong.',
    actionHint: _compact(raw),
  );
}

UserFacingError _mapAuthError(FirebaseAuthException error) {
  switch (error.code) {
    case 'network-request-failed':
      return const UserFacingError(
        message: 'Sign-in failed due to network issues.',
        actionHint: 'Check internet and retry.',
      );
    case 'sign_in_failed':
    case 'invalid-credential':
      return const UserFacingError(
        message: 'Google sign-in failed.',
        actionHint:
            'Retry sign-in and ensure Google Play services are updated.',
      );
    case 'account-exists-with-different-credential':
      return const UserFacingError(
        message: 'An account already exists with a different sign-in method.',
      );
    default:
      final fallback = error.message ?? error.code;
      return UserFacingError(
        message: 'Authentication failed.',
        actionHint: _compact(fallback),
      );
  }
}

UserFacingError _mapFirebaseError(FirebaseException error) {
  switch (error.code) {
    case 'permission-denied':
      return const UserFacingError(
        message: 'Permission denied for this operation.',
        actionHint:
            'If rules were just changed, deploy rules and retry after refresh.',
      );
    case 'unavailable':
    case 'network-request-failed':
      return const UserFacingError(
        message: 'Service is temporarily unavailable.',
        actionHint: 'Check internet and retry.',
      );
    case 'deadline-exceeded':
      return const UserFacingError(
        message: 'The request timed out.',
        actionHint: 'Retry in a moment.',
      );
    default:
      final fallback = error.message ?? error.code;
      return UserFacingError(
        message: 'Request failed.',
        actionHint: _compact(fallback),
      );
  }
}

String _compact(String value) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= 140) {
    return compact;
  }
  return '${compact.substring(0, 137)}...';
}
