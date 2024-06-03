// // Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// // for details. All rights reserved. Use of this source code is governed by a
// // BSD-style license that can be found in the LICENSE file.

// import 'dart:async';

// import 'package:macros/macros.dart';


// macro class ExecutionTraceMacro
//     implements ClassDeclarationsMacro, ClassDefinitionMacro, LibraryDeclarationsMacro, LibraryDefinitionMacro, ClassTypesMacro {
//   const ExecutionTraceMacro();

//   @override
//   void buildDeclarationsForClass(
//       ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
//         final clazzName = clazz.identifier.name;
//         final mixinName = '${clazzName}Mixin';
//     // var methods = await builder.methodsOf(clazz);
//     // if (methods.any((d) => d.identifier.name == 'dispose')) {
//     //   // Don't need to add the dispose method, it already exists.
//     //   return;
//     // }


//     // builder.declareInType(DeclarationCode.fromParts([
//     //   '@override\n',
//     //   // TODO: Remove external once the CFE supports it.
//     //   ' void add(){}',
//     // ]));

//     // builder.declareInLibrary(DeclarationCode.fromParts([
//     //   RawCode.fromParts([
//     //   'mixin $mixinName on $clazzName { void add() { } }',])
//     // ]));
//   }

//   @override
//   Future<void> buildDefinitionForClass(
//       ClassDeclaration clazz, TypeDefinitionBuilder builder) async {
//     // var disposableIdentifier =
//     //     // ignore: deprecated_member_use
//     //     await builder.resolveIdentifier(
//     //         Uri.parse('package:glance/src/modify_code_macro.dart'),
//     //         'Disposable');
//     // var disposableType = await builder
//     //     .resolve(NamedTypeAnnotationCode(name: disposableIdentifier));

//     // var disposeCalls = <Code>[];
//     // var fields = await builder.fieldsOf(clazz);
//     // for (var field in fields) {
//     //   var type = await builder.resolve(field.type.code);
//     //   if (!await type.isSubtypeOf(disposableType)) continue;
//     //   disposeCalls.add(RawCode.fromParts([
//     //     '\n',
//     //     field.identifier,
//     //     if (field.type.isNullable) '?',
//     //     '.dispose();',
//     //   ]));
//     // }

//     // Augment the dispose method by injecting all the new dispose calls after
//     // either a call to `augmented()` or `super.dispose()`, depending on if
//     // there already is an existing body to call.
//     //
//     // If there was an existing body, it is responsible for calling
//     // `super.dispose()`.
//     // var disposeMethod = (await builder.methodsOf(clazz))
//     //     .firstWhere((method) => method.identifier.name == 'dispose');
//     // var disposeBuilder = await builder.buildMethod(disposeMethod.identifier);
//     // disposeBuilder.augment(FunctionBodyCode.fromParts([
//     //   '{\n',
//     //   if (disposeMethod.hasExternal || !disposeMethod.hasBody)
//     //     'super.dispose();'
//     //   else
//     //     'augmented();',
//     //   ...disposeCalls,
//     //   '}',
//     // ]));

    
//   }

  

//   @override
//   FutureOr<void> buildDeclarationsForLibrary(Library library, DeclarationBuilder builder) async {
//     // final List<TypeDeclaration> typeDeclarations = await builder.typesOf(library);
//     // final names = <String>[];
//     // for (final t in typeDeclarations) {
//     //   if (t is ClassDeclaration) {
//     //     final classDecl = t as ClassDeclaration;
//     //     names.add(classDecl.identifier.name);
//     //   }
//     // }

//     // for (final name in names) {
//     //   final mixinName = '${name}Mixin';
//     //       builder.declareInLibrary(DeclarationCode.fromParts([
//     //   RawCode.fromParts([
//     //   'mixin $mixinName on $name { void add() { } }',])
//     // ]));

//     //   // builder.declareInLibrary(DeclarationCode.fromParts([
//     //   //   'mixin ${name}Mixin {',
//     //   //   '}',
//     //   // ]));
//     //   // builder.declareInLibrary(DeclarationCode.fromParts([
//     //   //   RawCode.fromParts([
//     //   //   'external mixin ${name}Mixin',
//     //   //   ])
//     //   // ]));
//     // }

//   }

//   @override
//   FutureOr<void> buildDefinitionForLibrary(Library library, LibraryDefinitionBuilder builder)  async {
//     //     final List<TypeDeclaration> typeDeclarations = await builder.typesOf(library);
//     // final names = <String>[];
//     // for (final t in typeDeclarations) {
//     //   if (t is ClassDeclaration) {
//     //     final classDecl = t as ClassDeclaration;
//     //     names.add(classDecl.identifier.name);

//     //     final classBuilder = (await builder.buildType(classDecl.identifier));
//     //     // builder.buildType(identifier)

//     //         var disposeMethods = (await classBuilder.methodsOf(classDecl));
//     // for (final m in disposeMethods) {
//     //   var disposeBuilder = await classBuilder.buildMethod(m.identifier);
      
//     // disposeBuilder.augment(FunctionBodyCode.fromParts([
//     //   '{\n',
//     //   // if (m.hasExternal || !m.hasBody)
//     //   //   'super.dispose();'
//     //   // else
//     //   'print(\'start\');\n',
//     //     'augmented();\n',
//     //   'print(\'end\');\n',
//     //   '}',
//     // ]));
//     // }
//     //   }
//     // }

   
//   }
  
//   @override
//   FutureOr<void> buildTypesForClass(ClassDeclaration clazz, ClassTypeBuilder builder) {
//     final mixinName = '${clazz.identifier.name}Mixin';
//     builder.declareType(
//       mixinName,
//       DeclarationCode.fromParts([
//         'mixin class $mixinName{}'
//       ]),
//     );

//     builder.appendMixins([RawTypeAnnotationCode.fromString(mixinName)]);
//   }
// }