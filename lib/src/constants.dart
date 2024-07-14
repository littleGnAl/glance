/// The default threshold for identifying jank (performance lag).
/// This is set to 32 milliseconds by default, which is equivalent to 2 frames
/// (each frame being 16 milliseconds).
const int kDefaultJankThreshold = 32;

/// The default sample rate for measuring performance in milliseconds.
/// Each sample is taken every 16 milliseconds by default.
const int kDefaultSampleRateInMilliseconds = 16;

/// Default filters for filtering module paths.
const kDefaultModulePathFilters = <String>[
  r'(.*)libflutter.so',
  r'(.*)libapp.so',
];

/// The header line used in Glance stack traces.
///
/// This string is used to identify the start of a stack trace in the
/// Glance stack traces format.
const kGlanceStackTraceHeaderLine =
    '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***';

/// The delimiter used for splitting lines in a Glance stack trace.
const kGlanceStackTraceLineSpilt = ' ';
