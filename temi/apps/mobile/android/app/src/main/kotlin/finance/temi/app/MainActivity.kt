package finance.temi.app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by `local_auth`:
// the biometric prompt is a FragmentActivity-hosted dialog (P7 security lock).
class MainActivity : FlutterFragmentActivity()
