// import 'package:glance/src/collect_stack.dart';

// abstract class GlanceStackTrace {
//   // Map<String, Object?> toJson();
// }

// // const glaceStackTraceHeaderLine =
// //     '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***';

// // const glaceStackTraceLineSpilt = ' ';

// class GlanceStackTraceImpl implements GlanceStackTrace {
//   GlanceStackTraceImpl(this.stackTraces);
//   final List<AggregatedNativeFrame> stackTraces;

//   // static const _headerLine =
//   //     '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***';
//   // static const _spilt = ' ';
//   // static const _baseAddrKey = 'base_addr';
//   // static const _pcKey = 'pc';

//   /// *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
//   /// #00  0000000000000640 0000000000042f89 30  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)   exec_time 30
//   /// #00  0000000000000640 0000000000042f89 30  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)   exec_time 30
//   /// #00  0000000000000640 0000000000042f89 30  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)   exec_time 30
//   /// #00  0000000000000640 0000000000042f89 30  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)   exec_time 30
//   /// #01  base_addr 0000000000000640  pc 0000000000000640  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::runCrashThread())         ~30
//   /// #02  base_addr 0000000000000640  pc 0000000000065a3b  /system/lib/libc.so (__pthread_start(void*))                                                   ~30
//   /// #03  base_addr 0000000000000640  pc 000000000001e4fd  /system/lib/libc.so (__start_thread)
//   /// *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
//   @override
//   String toString() {
//     final stringBuffer = StringBuffer();
//     stringBuffer.writeln(glaceStackTraceHeaderLine);
//     for (int i = 0; i < stackTraces.length; ++i) {
//       final stackTrace = stackTraces[i];
//       final frame = stackTrace.frame;
//       final occurTimes = stackTrace.occurTimes;
//       stringBuffer.write('#${i.toString().padLeft(3, ' ')}');
//       stringBuffer.write(glaceStackTraceLineSpilt);
//       stringBuffer.write(frame.module!.baseAddress);
//       stringBuffer.write(glaceStackTraceLineSpilt);
//       stringBuffer.write(frame.pc);
//       stringBuffer.write(glaceStackTraceLineSpilt);
//       stringBuffer.write(occurTimes);
//       stringBuffer.write(glaceStackTraceLineSpilt);
//       stringBuffer.write(frame.module!.path); // Is it necessary?
//       stringBuffer.writeln();
//     }

//     // stackTraces.map((e) {
//     //     final frame = e.frame;
//     //     final spent = e.timestampInMacros;
//     //     return {
//     //       "pc": frame.pc.toString(),
//     //       "timestamp": frame.timestamp,
//     //       if (frame.module != null)
//     //         "baseAddress": frame.module!.baseAddress.toString(),
//     //       if (frame.module != null) "path": frame.module!.path,
//     //       'spent': spent,
//     //     };
//     //   }).toList()

//     return stringBuffer.toString();
//   }
// }
