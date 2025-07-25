import 'dart:async';
import 'package:flutter_gl_flutterflow/flutter_gl.dart';
import 'package:three_dart_flutterflow/three_dart.dart';

import 'index.dart';

// o object_name | g group_name
var _objectPattern = RegExp("^[og]s*(.+)?");
// mtllib file_reference
var _materialLibraryPattern = RegExp("^mtllib ");
// usemtl material_name
var _materialUsePattern = RegExp("^usemtl ");
// usemap map_name
var _mapUsePattern = RegExp("^usemap ");

var _vA = Vector3();
var _vB = Vector3();
var _vC = Vector3();

var _ab = Vector3();
var _cb = Vector3();

class ParseStateMaterial {
  late dynamic index;
  late dynamic name;
  late dynamic mtllib;
  late dynamic smooth;
  late int groupStart;
  late int groupEnd;
  late int groupCount;
  late dynamic inherited;

  ParseStateMaterial(Map<String, dynamic> options) {
    index = options["index"];
    name = options["name"];
    mtllib = options["mtllib"];
    smooth = options["smooth"];
    groupStart = options["groupStart"] ?? 0;
    groupEnd = options["groupEnd"] ?? 0;
    groupCount = options["groupCount"] ?? 0;
    inherited = options["inherited"];
  }

  clone(index) {
    var cloned = ParseStateMaterial({
      "index": (index is num ? index : this.index),
      "name": name,
      "mtllib": mtllib,
      "smooth": smooth,
      "groupStart": 0,
      "groupEnd": -1,
      "groupCount": -1,
      "inherited": false
    });

    return cloned;
  }
}

class ParseStateObject {
  String name = "";
  bool fromDeclaration = false;
  List materials = [];
  Map<String, dynamic> geometry = {"vertices": [], "normals": [], "colors": [], "uvs": [], "hasUVIndices": false};
  bool smooth = true;

  ParseStateObject(Map<String, dynamic> options) {
    name = options["name"];
    fromDeclaration = options["fromDeclaration"];
  }

  startMaterial(name, libraries) {
    var previous = _finalize(false);

    // New usemtl declaration overwrites an inherited material, except if faces were declared
    // after the material, then it must be preserved for proper MultiMaterial continuation.
    if (previous != null && (previous.inherited || previous.groupCount <= 0)) {
      splice(materials, previous.index, 1);
    }

    var material = ParseStateMaterial({
      "index": materials.length,
      "name": name ?? '',
      "mtllib": (libraries is List && libraries.isNotEmpty ? libraries[libraries.length - 1] : ''),
      "smooth": (previous != null ? previous.smooth : smooth),
      "groupStart": (previous != null ? previous.groupEnd : 0),
      "groupEnd": -1,
      "groupCount": -1,
      "inherited": false
    });

    materials.add(material);

    return material;
  }

  currentMaterial() {
    if (materials.isNotEmpty) {
      return materials[materials.length - 1];
    }

    return null;
  }

  _finalize(end) {
    var lastMultiMaterial = currentMaterial();
    if (lastMultiMaterial != null && lastMultiMaterial.groupEnd == -1) {
      lastMultiMaterial.groupEnd = geometry["vertices"]!.length ~/ 3;
      lastMultiMaterial.groupCount = lastMultiMaterial.groupEnd - lastMultiMaterial.groupStart;
      lastMultiMaterial.inherited = false;
    }

    // Ignore objects tail materials if no face declarations followed them before a new o/g started.
    if (end && materials.length > 1) {
      for (var mi = materials.length - 1; mi >= 0; mi--) {
        if (materials[mi].groupCount <= 0) {
          splice(materials, mi, 1);
        }
      }
    }

    // Guarantee at least one empty material, this makes the creation later more straight forward.
    if (end && materials.isEmpty) {
      materials.add(ParseStateMaterial({"name": '', "smooth": smooth}));
    }

    return lastMultiMaterial;
  }
}

class ParserState {
  var objects = [];
  ParseStateObject? object;

  List<double> vertices = [];
  List<double> normals = [];
  List<double> colors = [];
  List<double> uvs = [];

  var materials = {};
  var materialLibraries = [];

  ParserState() {
    startObject("", false);
  }

  startObject(name, fromDeclaration) {
    // print(" startObject name: ${name} fromDeclaration: ${fromDeclaration} ");
    // print(" startObject object: ${this.object} this.object.fromDeclaration: ${this.object?.fromDeclaration} ");
    // If the current object (initial from reset) is not from a g/o declaration in the parsed
    // file. We need to use it for the first parsed g/o to keep things in sync.
    if (object != null && object!.fromDeclaration == false) {
      object!.name = name;
      object!.fromDeclaration = (fromDeclaration != false);
      return;
    }

    var previousMaterial = object != null ? object!.currentMaterial() : null;

    if (object != null) {
      object!._finalize(true);
    }

    object = ParseStateObject({
      "name": name ?? '',
      "fromDeclaration": (fromDeclaration != false),
    });

    // Inherit previous objects material.
    // Spec tells us that a declared material must be set to all objects until a new material is declared.
    // If a usemtl declaration is encountered while this new object is being parsed, it will
    // overwrite the inherited material. Exception being that there was already face declarations
    // to the inherited material, then it will be preserved for proper MultiMaterial continuation.

    if (previousMaterial != null && previousMaterial.name != null) {
      var declared = previousMaterial.clone(0);
      declared.inherited = true;
      object!.materials.add(declared);
    }

    objects.add(object);
  }

  finalize() {
    if (object != null) {
      object!._finalize(true);
    }
  }

  parseVertexIndex(value, len) {
    var index = int.parse(value, radix: 10);
    return (index >= 0 ? index - 1 : index + len / 3) * 3;
  }

  parseNormalIndex(value, len) {
    var index = int.parse(value, radix: 10);
    return (index >= 0 ? index - 1 : index + len / 3) * 3;
  }

  parseUVIndex(value, len) {
    var index = int.parse(value, radix: 10);
    return (index >= 0 ? index - 1 : index + len / 2) * 2;
  }

  addVertex(a, b, c) {
    var src = vertices;
    var dst = object!.geometry["vertices"];

    dst.addAll([src[a + 0], src[a + 1], src[a + 2]]);
    dst.addAll([src[b + 0], src[b + 1], src[b + 2]]);
    dst.addAll([src[c + 0], src[c + 1], src[c + 2]]);
  }

  addVertexPoint(a) {
    var src = vertices;
    var dst = object!.geometry["vertices"];

    dst.addAll([src[a + 0], src[a + 1], src[a + 2]]);
  }

  addVertexLine(a) {
    var src = vertices;
    var dst = object!.geometry["vertices"];

    dst.addAll([src[a + 0], src[a + 1], src[a + 2]]);
  }

  addNormal(a, b, c) {
    var src = normals;
    var dst = object!.geometry["normals"];

    dst.addAll([src[a + 0], src[a + 1], src[a + 2]]);
    dst.addAll([src[b + 0], src[b + 1], src[b + 2]]);
    dst.addAll([src[c + 0], src[c + 1], src[c + 2]]);
  }

  addFaceNormal(a, b, c) {
    var src = vertices;
    var dst = object!.geometry["normals"];

    _vA.fromArray(src, a);
    _vB.fromArray(src, b);
    _vC.fromArray(src, c);

    _cb.subVectors(_vC, _vB);
    _ab.subVectors(_vA, _vB);
    _cb.cross(_ab);

    _cb.normalize();

    dst.addAll([_cb.x, _cb.y, _cb.z]);
    dst.addAll([_cb.x, _cb.y, _cb.z]);
    dst.addAll([_cb.x, _cb.y, _cb.z]);
  }

  addColor(a, b, c) {
    var src = colors;
    var dst = object!.geometry["colors"];

    if (src.length > a) dst.addAll([src[a + 0], src[a + 1], src[a + 2]]);
    if (b != null && src.length > b) dst.addAll([src[b + 0], src[b + 1], src[b + 2]]);
    if (c != null && src.length > c) dst.addAll([src[c + 0], src[c + 1], src[c + 2]]);
  }

  addUV(a, b, c) {
    var src = uvs;
    var dst = object!.geometry["uvs"];

    dst.addAll([src[a + 0], src[a + 1]]);
    dst.addAll([src[b + 0], src[b + 1]]);
    dst.addAll([src[c + 0], src[c + 1]]);
  }

  addDefaultUV() {
    var dst = object!.geometry["uvs"];

    dst.addAll([0, 0]);
    dst.addAll([0, 0]);
    dst.addAll([0, 0]);
  }

  addUVLine(a) {
    var src = uvs;
    var dst = object!.geometry["uvs"];

    dst.addAll([src[a + 0], src[a + 1]]);
  }

  addFace(a, b, c, ua, ub, uc, na, nb, nc) {
    var vLen = vertices.length;

    var ia = parseVertexIndex(a, vLen);
    var ib = parseVertexIndex(b, vLen);
    var ic = parseVertexIndex(c, vLen);

    addVertex(ia, ib, ic);
    addColor(ia, ib, ic);

    // normals

    if (na != null && na != '') {
      var nLen = normals.length;

      ia = parseNormalIndex(na, nLen);
      ib = parseNormalIndex(nb, nLen);
      ic = parseNormalIndex(nc, nLen);

      addNormal(ia, ib, ic);
    } else {
      addFaceNormal(ia, ib, ic);
    }

    // uvs

    if (ua != null && ua != '') {
      var uvLen = uvs.length;

      ia = parseUVIndex(ua, uvLen);
      ib = parseUVIndex(ub, uvLen);
      ic = parseUVIndex(uc, uvLen);

      addUV(ia, ib, ic);

      object!.geometry["hasUVIndices"] = true;
    } else {
      // add placeholder values (for inconsistent face definitions)

      addDefaultUV();
    }
  }

  addPointGeometry(vertices) {
    object!.geometry["type"] = 'Points';

    var vLen = this.vertices.length;

    for (var vi = 0, l = vertices.length; vi < l; vi++) {
      var index = parseVertexIndex(vertices[vi], vLen);

      addVertexPoint(index);
      addColor(index, null, null);
    }
  }

  addLineGeometry(vertices, uvs) {
    object!.geometry["type"] = 'Line';

    var vLen = this.vertices.length;
    var uvLen = this.uvs.length;

    for (var vi = 0, l = vertices.length; vi < l; vi++) {
      addVertexLine(parseVertexIndex(vertices[vi], vLen));
    }

    for (var uvi = 0, l = uvs.length; uvi < l; uvi++) {
      addUVLine(parseUVIndex(uvs[uvi], uvLen));
    }
  }
}

//

class OBJLoader extends Loader {
  MaterialCreator? materials;

  OBJLoader(manager) : super(manager);

  @override
  loadAsync(url) async {
    var completer = Completer();

    load(url, (buffer) {
      completer.complete(buffer);
    });

    return completer.future;
  }

  @override
  load(url, onLoad, [onProgress, onError]) {
    var scope = this;

    var loader = FileLoader(manager);
    loader.setPath(path);
    loader.setRequestHeader(requestHeader);
    loader.setWithCredentials(withCredentials);
    loader.load(url, (text) async {
      // try {

      onLoad(await scope.parse(text));

      // } catch ( e ) {

      // 	if ( onError != null ) {

      // 		onError( e );

      // 	} else {

      // 		print( e );

      // 	}

      // 	scope.manager.itemError( url );

      // }
    }, onProgress, onError);
  }

  setMaterials(materials) {
    this.materials = materials;

    return this;
  }

  @override
  parse(json, [String? path, Function? onLoad, Function? onError]) async {
    var state = ParserState();

    if (json.indexOf('\r\n') != -1) {
      // This is faster than String.split with regex that splits on both
      json = json.replaceAll(RegExp("\r\n", multiLine: true), '\n');
    }

    if (json.indexOf('\\\n') != -1) {
      // join lines separated by a line continuation character (\)
      json = json.replaceAll(RegExp("\\\n"), '');
    }

    var lines = json.split('\n');
    var line = '', lineFirstChar = '';
    var lineLength = 0;
    var result = [];

    // Faster to just trim left side of the line. Use if available.

    for (var i = 0, l = lines.length; i < l; i++) {
      line = lines[i];

      line = line.trimLeft();

      // print("i: ${i} line: ${line} ");

      lineLength = line.length;

      if (lineLength == 0) continue;

      lineFirstChar = line[0];

      // @todo invoke passed in handler if any
      if (lineFirstChar == '#') continue;

      if (lineFirstChar == 'v') {
        var data = line.split(RegExp(r"\s+"));

        switch (data[0]) {
          case 'v':
            state.vertices.addAll([parseFloat(data[1]), parseFloat(data[2]), parseFloat(data[3])]);
            if (data.length >= 7) {
              state.colors.addAll([parseFloat(data[4]), parseFloat(data[5]), parseFloat(data[6])]);
            } else {
              // if no colors are defined, add placeholders so color and vertex indices match
              state.colors.addAll([]);
            }

            break;
          case 'vn':
            state.normals.addAll([parseFloat(data[1]), parseFloat(data[2]), parseFloat(data[3])]);
            break;
          case 'vt':
            state.uvs.addAll([parseFloat(data[1]), parseFloat(data[2])]);
            break;
        }
      } else if (lineFirstChar == 'f') {
        var lineData = line.substring(1).trim();
        var vertexData = lineData.split(RegExp(r"\s+"));
        List<List> faceVertices = [];

        // Parse the face vertex data into an easy to work with format

        // print(" lineFirstChar is f .................. ");
        // print(vertexData);

        for (var j = 0, jl = vertexData.length; j < jl; j++) {
          var vertex = vertexData[j];

          if (vertex.isNotEmpty) {
            var vertexParts = vertex.split('/');
            faceVertices.add(vertexParts);
          }
        }

        // Draw an edge between the first vertex and all subsequent vertices to form an n-gon

        var v1 = faceVertices[0];

        for (var j = 1, jl = faceVertices.length - 1; j < jl; j++) {
          var v2 = faceVertices[j];
          var v3 = faceVertices[j + 1];

          state.addFace(
              v1[0],
              v2[0],
              v3[0],
              v1.length > 1 ? v1[1] : null,
              v2.length > 1 ? v2[1] : null,
              v3.length > 1 ? v3[1] : null,
              v1.length > 2 ? v1[2] : null,
              v2.length > 2 ? v2[2] : null,
              v3.length > 2 ? v3[2] : null);
        }
      } else if (lineFirstChar == 'l') {
        var lineParts = line.substring(1).trim().split(' ');
        var lineVertices = [];
        var lineUVs = [];

        if (!line.contains('/')) {
          lineVertices = lineParts;
        } else {
          for (var li = 0, llen = lineParts.length; li < llen; li++) {
            var parts = lineParts[li].split('/');

            if (parts[0] != '') lineVertices.add(parts[0]);
            if (parts[1] != '') lineUVs.add(parts[1]);
          }
        }

        state.addLineGeometry(lineVertices, lineUVs);
      } else if (lineFirstChar == 'p') {
        var lineData = line.substring(1).trim();
        var pointData = lineData.split(' ');

        state.addPointGeometry(pointData);
      } else if (_objectPattern.hasMatch(line)) {
        result = _objectPattern.allMatches(line).toList();

        // o object_name
        // or
        // g group_name

        // WORKAROUND: https://bugs.chromium.org/p/v8/issues/detail?id=2869
        // var name = result[ 0 ].substr( 1 ).trim();
        var name = ' ${result[0].group(0).substring(1).trim()}'.substring(1);

        state.startObject(name, null);
      } else if (_materialUsePattern.hasMatch(line)) {
        // material

        state.object!.startMaterial(line.substring(7).trim(), state.materialLibraries);
      } else if (_materialLibraryPattern.hasMatch(line)) {
        // mtl file

        state.materialLibraries.add(line.substring(7).trim());
      } else if (_mapUsePattern.hasMatch(line)) {
        // the line is parsed but ignored since the loader assumes textures are defined MTL files
        // (according to https://www.okino.com/conv/imp_wave.htm, 'usemap' is the old-style Wavefront texture reference method)

        print('THREE.OBJLoader: Rendering identifier "usemap" not supported. Textures must be defined in MTL files.');
      } else if (lineFirstChar == 's') {
        result = line.split(' ');

        // smooth shading

        // @todo Handle files that have varying smooth values for a set of faces inside one geometry,
        // but does not define a usemtl for each face set.
        // This should be detected and a dummy material created (later MultiMaterial and geometry groups).
        // This requires some care to not create extra material on each smooth value for "normal" obj files.
        // where explicit usemtl defines geometry groups.
        // Example asset: examples/models/obj/cerberus/Cerberus.obj

        /*
					 * http://paulbourke.net/dataformats/obj/
					 * or
					 * http://www.cs.utah.edu/~boulos/cs3505/obj_spec.pdf
					 *
					 * From chapter "Grouping" Syntax explanation "s group_number":
					 * "group_number is the smoothing group number. To turn off smoothing groups, use a value of 0 or off.
					 * Polygonal elements use group numbers to put elements in different smoothing groups. For free-form
					 * surfaces, smoothing groups are either turned on or off; there is no difference between values greater
					 * than 0."
					 */
        if (result.length > 1) {
          var value = result[1].trim().toLowerCase();
          state.object!.smooth = (value != '0' && value != 'off');
        } else {
          // ZBrush can produce "s" lines #11707
          state.object!.smooth = true;
        }

        var material = state.object!.currentMaterial();
        if (material != null) material.smooth = state.object!.smooth;
      } else {
        // Handle null terminated files without exception
        if (line == '0') continue;

        print('THREE.OBJLoader: Unexpected line: "$line"');
      }
    }

    state.finalize();

    var container = Group();
    // container.materialLibraries = [].concat( state.materialLibraries );

    var hasPrimitives = !(state.objects.length == 1 && state.objects[0].geometry["vertices"].length == 0);

    if (hasPrimitives == true) {
      for (var i = 0, l = state.objects.length; i < l; i++) {
        var object = state.objects[i];
        var geometry = object.geometry;
        var materials = object.materials;
        var isLine = (geometry["type"] == 'Line');
        var isPoints = (geometry["type"] == 'Points');
        var hasVertexColors = false;

        // Skip o/g line declarations that did not follow with any faces
        if (geometry["vertices"].length == 0) continue;

        var buffergeometry = BufferGeometry();

        buffergeometry.setAttribute(
            'position', Float32BufferAttribute(Float32Array.fromList(List<double>.from(geometry["vertices"])), 3));

        if (geometry["normals"].length > 0) {
          buffergeometry.setAttribute(
              'normal', Float32BufferAttribute(Float32Array.fromList(List<double>.from(geometry["normals"])), 3));
        }

        if (geometry["colors"].length > 0) {
          hasVertexColors = true;
          buffergeometry.setAttribute(
              'color', Float32BufferAttribute(Float32Array.fromList(List<double>.from(geometry["colors"])), 3));
        }

        if (geometry["hasUVIndices"] == true) {
          buffergeometry.setAttribute(
              'uv', Float32BufferAttribute(Float32Array.fromList(List<double>.from(geometry["uvs"])), 2));
        }

        // Create materials

        var createdMaterials = [];

        for (var mi = 0, miLen = materials.length; mi < miLen; mi++) {
          var sourceMaterial = materials[mi];
          var materialHash = sourceMaterial.name + '_' + "${sourceMaterial.smooth}" + '_' + "$hasVertexColors";
          var material = state.materials[materialHash];

          if (this.materials != null) {
            material = await this.materials!.create(sourceMaterial.name);

            // mtl etc. loaders probably can't create line materials correctly, copy properties to a line material.
            if (isLine && material && material is! LineBasicMaterial) {
              var materialLine = LineBasicMaterial({});
              materialLine.copy(material);
              // Material.prototype.copy.call( materialLine, material );
              materialLine.color.copy(material.color);
              material = materialLine;
            } else if (isPoints && material && material is! PointsMaterial) {
              var materialPoints = PointsMaterial({"size": 10, "sizeAttenuation": false});
              // Material.prototype.copy.call( materialPoints, material );
              materialPoints.copy(material);
              materialPoints.color.copy(material.color);
              materialPoints.map = material.map;
              material = materialPoints;
            }
          }

          if (material == null) {
            if (isLine) {
              material = LineBasicMaterial({});
            } else if (isPoints) {
              material = PointsMaterial({"size": 1, "sizeAttenuation": false});
            } else {
              material = MeshPhongMaterial();
            }

            material.name = sourceMaterial.name;
            material.flatShading = sourceMaterial.smooth ? false : true;
            material.vertexColors = hasVertexColors;

            state.materials[materialHash] = material;
          }

          createdMaterials.add(material);
        }

        // Create mesh
        var mesh;

        if (createdMaterials.length > 1) {
          for (var mi = 0, miLen = materials.length; mi < miLen; mi++) {
            var sourceMaterial = materials[mi];
            buffergeometry.addGroup(sourceMaterial.groupStart.toInt(), sourceMaterial.groupCount.toInt(), mi);
          }

          if (isLine) {
            mesh = LineSegments(buffergeometry, createdMaterials);
          } else if (isPoints) {
            mesh = Points(buffergeometry, createdMaterials);
          } else {
            mesh = Mesh(buffergeometry, createdMaterials);
          }
        } else {
          if (isLine) {
            mesh = LineSegments(buffergeometry, createdMaterials[0]);
          } else if (isPoints) {
            mesh = Points(buffergeometry, createdMaterials[0]);
          } else {
            mesh = Mesh(buffergeometry, createdMaterials[0]);
          }
        }

        mesh.name = object.name;

        container.add(mesh);
      }
    } else {
      // if there is only the default parser state object with no geometry data, interpret data as point cloud

      if (state.vertices.isNotEmpty) {
        var material = PointsMaterial({"size": 1, "sizeAttenuation": false});

        var buffergeometry = BufferGeometry();

        buffergeometry.setAttribute('position', Float32BufferAttribute(Float32Array.fromList(state.vertices), 3));

        if (state.colors.isNotEmpty) {
          buffergeometry.setAttribute('color', Float32BufferAttribute(Float32Array.fromList(state.colors), 3));
          material.vertexColors = true;
        }

        var points = Points(buffergeometry, material);
        container.add(points);
      }
    }

    return container;
  }
}
