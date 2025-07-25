import 'dart:typed_data';
import 'package:three_dart_flutterflow/three_dart.dart';

import 'package:typr_dart/typr_dart.dart' as typr_dart;

/// Requires opentype.js to be included in the project.
/// Loads TTF files and converts them into typeface JSON that can be used directly
/// to create THREE.Font objects.

class TYPRLoader extends Loader {
  bool reversed = false;

  TYPRLoader(manager) : super(manager);

  @override
  loadAsync(url) async {
    var loader = FileLoader(manager);
    loader.setPath(path);
    loader.setResponseType('arraybuffer');
    loader.setRequestHeader(requestHeader);
    loader.setWithCredentials(withCredentials);
    var buffer = await loader.loadAsync(url);

    return _parse(buffer);
  }

  @override
  load(url, onLoad, [onProgress, onError]) {
    var scope = this;

    var loader = FileLoader(manager);
    loader.setPath(path);
    loader.setResponseType('arraybuffer');
    loader.setRequestHeader(requestHeader);
    loader.setWithCredentials(withCredentials);
    loader.load(url, (buffer) {
      // try {

      onLoad(scope._parse(buffer));

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

  _parse(Uint8List arraybuffer) {
    convert(typr_dart.Font font, reversed) {
      // var round = Math.round;

      // var glyphs = {};
      // var scale = (100000) / ((font.head["unitsPerEm"] ?? 2048) * 72);

      // var numGlyphs = font.maxp["numGlyphs"];

      // for ( var i = 0; i < numGlyphs; i ++ ) {

      // 	var path = font.glyphToPath(i);

      //   // print(path);

      // 	if ( path != null ) {
      //     var aWidths = font.hmtx["aWidth"];

      //     path["ha"] = round( aWidths[i] * scale );

      //     var crds = path["crds"];
      //     List<num> _scaledCrds = [];

      //     crds.forEach((nrd) {
      //       _scaledCrds.add(nrd * scale);
      //     });

      //     path["crds"] = _scaledCrds;

      // 		glyphs[i ] = path;

      // 	}

      // }

      return {
        "font": font,
        "familyName": font.getFamilyName(),
        "fullName": font.getFullName(),
        "underlinePosition": font.post["underlinePosition"],
        "underlineThickness": font.post["underlineThickness"],
        "boundingBox": {
          "xMin": font.head["xMin"],
          "xMax": font.head["xMax"],
          "yMin": font.head["yMin"],
          "yMax": font.head["yMax"]
        },
        "resolution": 1000,
        "original_font_information": font.name
      };
    }

    return convert(typr_dart.Font(arraybuffer), reversed); // eslint-disable-line no-undef
  }
}
