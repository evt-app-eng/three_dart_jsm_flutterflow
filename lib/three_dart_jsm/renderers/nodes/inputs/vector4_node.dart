import 'package:three_dart_flutterflow/three_dart.dart';
import 'package:three_dart_jsm_flutterflow/three_dart_jsm/renderers/nodes/index.dart';

class Vector4Node extends InputNode {
  Vector4Node([value]) : super('vec4') {
    this.value = value ?? Vector4();
  }
}
