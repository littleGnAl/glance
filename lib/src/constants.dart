/// The default threshold for identifying UI jank.
const int kDefaultJankThreshold = 16;

/// The default sample rate for measuring performance in milliseconds.
const int kDefaultSampleRateInMilliseconds = 1;

/// Limits the maximum number of stack traces to 99. Any stack traces exceeding
/// `kMaxStackTraces` will be dropped.
const int kMaxStackTraces = 99;

/// Default filters for filtering module paths for Android.
/// This filter only includes `libflutter.so` and `libapp.so` by default.
const kAndroidDefaultModulePathFilters = <String>[
  r'(.*)libflutter.so',
  r'(.*)libapp.so',
];

/// Default filters for filtering module paths for iOS.
/// This filter only includes `App.framework` and `Flutter.framework` by default.
const kIOSDefaultModulePathFilters = <String>[
  r'(.*)App.framework(.*)',
  r'(.*)Flutter.framework(.*)',
];

/// The header line used in Glance stack traces.
///
/// This string is used to identify the start of a stack trace in the
/// Glance stack traces format.
const kGlanceStackTraceHeaderLine =
    '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***';

/// The delimiter used for splitting lines in a Glance stack trace.
const kGlanceStackTraceLineSpilt = ' ';
