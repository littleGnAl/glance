// @LibMacro()
<<<<<<< Updated upstream
// library my_lib;

// import 'package:glance/src/modify_code_macro.dart';

// // @JsonCodable() // Macro annotation.
// // @LibMacro()
// class User {
//   // final int? age;
//   // final String name;
//   // final String username;
=======
library my_lib;

import 'package:glance/src/execution_trace_macro.dart';
import 'package:glance/src/modify_code_macro.dart';

// @JsonCodable() // Macro annotation.
@ExecutionTraceMacro()
class User {
  // final int? age;
  // final String name;
  // final String username;
>>>>>>> Stashed changes

//   void add() {
//     int a = 1;
//     int b = 2;
//   }

//   //  User.fromJson(Map<String, Object?> json): this.age = json[''],
//   //   this.name = json[''],
//   //   this.username = json[''];
// }
