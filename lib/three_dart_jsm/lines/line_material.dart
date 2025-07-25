import 'package:three_dart_flutterflow/three_dart.dart';

/// parameters = {
///  color: <hex>,
///  linewidth: <float>,
///  dashed: <boolean>,
///  dashScale: <float>,
///  dashSize: <float>,
///  dashOffset: <float>,
///  gapSize: <float>,
///  resolution: <Vector2>, // to be set by renderer
/// }

final uniformsLibLine = {
  "linewidth": {"value": 1},
  "resolution": {"value": Vector2(1, 1)},
  "dashScale": {"value": 1},
  "dashSize": {"value": 1},
  "dashOffset": {"value": 0},
  "gapSize": {"value": 1}, // todo FIX - maybe change to totalSize
  "opacity": {"value": 1}
};

Map<String, dynamic> shaderLibLine = {
  "uniforms": UniformsUtils.merge([uniformsLib["common"], uniformsLib["fog"], uniformsLibLine]),
  "vertexShader": """
		#include <common>
		#include <color_pars_vertex>
		#include <fog_pars_vertex>
		#include <logdepthbuf_pars_vertex>
		#include <clipping_planes_pars_vertex>

		uniform float linewidth;
		uniform vec2 resolution;

		attribute vec3 instanceStart;
		attribute vec3 instanceEnd;

		attribute vec3 instanceColorStart;
		attribute vec3 instanceColorEnd;

		varying vec2 vUv;

		#ifdef USE_DASH

			uniform float dashScale;
			attribute float instanceDistanceStart;
			attribute float instanceDistanceEnd;
			varying float vLineDistance;

		#endif

		void trimSegment( const in vec4 start, inout vec4 end ) {

			// trim end segment so it terminates between the camera plane and the near plane

			// conservative estimate of the near plane
			float a = projectionMatrix[ 2 ][ 2 ]; // 3nd entry in 3th column
			float b = projectionMatrix[ 3 ][ 2 ]; // 3nd entry in 4th column
			float nearEstimate = - 0.5 * b / a;

			float alpha = ( nearEstimate - start.z ) / ( end.z - start.z );

			end.xyz = mix( start.xyz, end.xyz, alpha );

		}

		void main() {

			#ifdef USE_COLOR

				vColor.xyz = ( position.y < 0.5 ) ? instanceColorStart : instanceColorEnd;

			#endif

			#ifdef USE_DASH

				vLineDistance = ( position.y < 0.5 ) ? dashScale * instanceDistanceStart : dashScale * instanceDistanceEnd;

			#endif

			float aspect = resolution.x / resolution.y;

			vUv = uv;

			// camera space
			vec4 start = modelViewMatrix * vec4( instanceStart, 1.0 );
			vec4 end = modelViewMatrix * vec4( instanceEnd, 1.0 );

			// special case for perspective projection, and segments that terminate either in, or behind, the camera plane
			// clearly the gpu firmware has a way of addressing this issue when projecting into ndc space
			// but we need to perform ndc-space calculations in the shader, so we must address this issue directly
			// perhaps there is a more elegant solution -- WestLangley

			bool perspective = ( projectionMatrix[ 2 ][ 3 ] == - 1.0 ); // 4th entry in the 3rd column

			if ( perspective ) {

				if ( start.z < 0.0 && end.z >= 0.0 ) {

					trimSegment( start, end );

				} else if ( end.z < 0.0 && start.z >= 0.0 ) {

					trimSegment( end, start );

				}

			}

			// clip space
			vec4 clipStart = projectionMatrix * start;
			vec4 clipEnd = projectionMatrix * end;

			// ndc space
			vec2 ndcStart = clipStart.xy / clipStart.w;
			vec2 ndcEnd = clipEnd.xy / clipEnd.w;

			// direction
			vec2 dir = ndcEnd - ndcStart;

			// account for clip-space aspect ratio
			dir.x *= aspect;
			dir = normalize( dir );

			// perpendicular to dir
			vec2 offset = vec2( dir.y, - dir.x );

			// undo aspect ratio adjustment
			dir.x /= aspect;
			offset.x /= aspect;

			// sign flip
			if ( position.x < 0.0 ) offset *= - 1.0;

			// endcaps
			if ( position.y < 0.0 ) {

				offset += - dir;

			} else if ( position.y > 1.0 ) {

				offset += dir;

			}

			// adjust for linewidth
			offset *= linewidth;

			// adjust for clip-space to screen-space conversion // maybe resolution should be based on viewport ...
			offset /= resolution.y;

			// select end
			vec4 clip = ( position.y < 0.5 ) ? clipStart : clipEnd;

			// back to clip space
			offset *= clip.w;

			clip.xy += offset;

			gl_Position = clip;

			vec4 mvPosition = ( position.y < 0.5 ) ? start : end; // this is an approximation

			#include <logdepthbuf_vertex>
			#include <clipping_planes_vertex>
			#include <fog_vertex>

		}
		""",
  "fragmentShader": """
		uniform vec3 diffuse;
		uniform float opacity;

		#ifdef USE_DASH

			uniform float dashSize;
			uniform float dashOffset;
			uniform float gapSize;

		#endif

		varying float vLineDistance;

		#include <common>
		#include <color_pars_fragment>
		#include <fog_pars_fragment>
		#include <logdepthbuf_pars_fragment>
		#include <clipping_planes_pars_fragment>

		varying vec2 vUv;

		void main() {

			#include <clipping_planes_fragment>

			#ifdef USE_DASH

				if ( vUv.y < - 1.0 || vUv.y > 1.0 ) discard; // discard endcaps

				if ( mod( vLineDistance + dashOffset, dashSize + gapSize ) > dashSize ) discard; // todo - FIX

			#endif

			if ( abs( vUv.y ) > 1.0 ) {

				float a = vUv.x;
				float b = ( vUv.y > 0.0 ) ? vUv.y - 1.0 : vUv.y + 1.0;
				float len2 = a * a + b * b;

				if ( len2 > 1.0 ) discard;

			}

			vec4 diffuseColor = vec4( diffuse, opacity );

			#include <logdepthbuf_fragment>
			#include <color_fragment>

			gl_FragColor = vec4( diffuseColor.rgb, diffuseColor.a );

			#include <tonemapping_fragment>
			#include <encodings_fragment>
			#include <fog_fragment>
			#include <premultiplied_alpha_fragment>

		}
		"""
};

class LineMaterial extends ShaderMaterial {
  bool isLineMaterial = true;
  bool dashed = false;

  LineMaterial(parameters)
      : super({
          "uniforms": UniformsUtils.clone(shaderLibLine["uniforms"]),
          "vertexShader": shaderLibLine["vertexShader"],
          "fragmentShader": shaderLibLine["fragmentShader"],
          "clipping": true // required for clipping support
        }) {
    type = 'LineMaterial';
    setValues(parameters);
  }

  @override
  setValue(String key, dynamic newValue) {
    if (key == "dashed") {
      dashed = newValue;
    } else if (key == "resolution") {
      resolution = newValue;
    } else {
      super.setValue(key, newValue);
    }
  }

  @override
  get color => uniforms["diffuse"]["value"];
  @override
  set color(value) {
    uniforms["diffuse"]["value"] = value;
  }

  @override
  get linewidth => uniforms["linewidth"]["value"];
  @override
  set linewidth(value) {
    uniforms["linewidth"] = {"value": value};
  }

  get dashScale => uniforms["dashScale"]["value"];
  set dashScale(value) {
    uniforms["dashScale"]["value"] = value;
  }

  @override
  get dashSize => uniforms["dashSize"]["value"];
  @override
  set dashSize(value) {
    uniforms["dashSize"]["value"] = value;
  }

  get dashOffset => uniforms["dashOffset"]["value"];
  set dashOffset(value) {
    uniforms["dashOffset"]["value"] = value;
  }

  @override
  get gapSize => uniforms["gapSize"]["value"];
  @override
  set gapSize(value) {
    uniforms["gapSize"]["value"] = value;
  }

  @override
  get opacity => uniforms["opacity"]["value"];
  @override
  set opacity(value) {
    uniforms["opacity"]["value"] = value;
  }

  get resolution => uniforms["resolution"]["value"];
  set resolution(value) {
    uniforms["resolution"]["value"] = value;
  }
}
