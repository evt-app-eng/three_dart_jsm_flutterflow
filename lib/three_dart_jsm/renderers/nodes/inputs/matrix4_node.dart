import 'package:three_dart_flutterflow/three_dart.dart';
import 'package:three_dart_jsm_flutterflow/three_dart_jsm/renderers/nodes/index.dart';

class Matrix4Node extends InputNode {
  Matrix4Node([value]) : super('mat4') {
    generateLength = 2;
    this.value = value ?? Matrix4();
  }
}
