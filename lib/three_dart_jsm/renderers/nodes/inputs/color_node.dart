import 'package:three_dart_flutterflow/three_dart.dart';
import 'package:three_dart_jsm_flutterflow/three_dart_jsm/renderers/nodes/index.dart';

class ColorNode extends InputNode {
  ColorNode([value]) : super('color') {
    generateLength = 2;

    this.value = value ?? Color(1, 1, 1);
  }
}
