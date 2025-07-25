import 'package:flutter_gl_flutterflow/flutter_gl.dart';
import 'package:three_dart_flutterflow/three_dart.dart';

class LineSegments2 extends Mesh {
  bool isLineSegments2 = true;

  LineSegments2(geometry, material) : super(geometry, material) {
    type = "LineSegments2";
  }

  // if ( geometry === undefined ) geometry = new LineSegmentsGeometry();
  // if ( material === undefined ) material = new LineMaterial( { color: Math.random() * 0xffffff } );

  computeLineDistances() {
    // for backwards-compatability, but could be a method of LineSegmentsGeometry...

    var start = Vector3.init();
    var end = Vector3.init();

    var geometry = this.geometry!;

    var instanceStart = geometry.attributes["instanceStart"];
    var instanceEnd = geometry.attributes["instanceEnd"];
    var lineDistances = Float32Array((2 * instanceStart.data.count).toInt());

    for (var i = 0, j = 0, l = instanceStart.data.count; i < l; i++, j += 2) {
      start.fromBufferAttribute(instanceStart, i);
      end.fromBufferAttribute(instanceEnd, i);

      lineDistances[j] = (j == 0) ? 0.0 : lineDistances[j - 1];
      lineDistances[j + 1] = lineDistances[j] + start.distanceTo(end);
    }

    var instanceDistanceBuffer = InstancedInterleavedBuffer(lineDistances, 2, 1); // d0, d1

    geometry.setAttribute(
        'instanceDistanceStart', InterleavedBufferAttribute(instanceDistanceBuffer, 1, 0, false)); // d0
    geometry.setAttribute('instanceDistanceEnd', InterleavedBufferAttribute(instanceDistanceBuffer, 1, 1, false)); // d1

    return this;
  }

  @override
  raycast(Raycaster raycaster, intersects) {
    var start = Vector4.init();
    var end = Vector4.init();

    var ssOrigin = Vector4.init();
    var ssOrigin3 = Vector3.init();
    var mvMatrix = Matrix4();
    var line = Line3(null, null);
    var closestPoint = Vector3.init();

    if (raycaster.camera == null) {
      print('LineSegments2: "Raycaster.camera" needs to be set in order to raycast against LineSegments2.');
    }

    var threshold = (raycaster.params["Line2"] != null) ? raycaster.params["Line2"].threshold ?? 0 : 0;

    var ray = raycaster.ray;
    var camera = raycaster.camera;
    var projectionMatrix = camera?.projectionMatrix ?? Matrix4();

    var geometry = this.geometry!;
    var material = this.material;
    var resolution = material.resolution;
    var lineWidth = material.linewidth + threshold;

    var instanceStart = geometry.attributes["instanceStart"];
    var instanceEnd = geometry.attributes["instanceEnd"];

    // pick a point 1 unit out along the ray to avoid the ray origin
    // sitting at the camera origin which will cause "w" to be 0 when
    // applying the projection matrix.
    ray.at(1, ssOrigin);
    // TODO ray.at need Vec3 but ssOrigin is vec4

    // ndc space [ - 1.0, 1.0 ]
    ssOrigin.w = 1;
    ssOrigin.applyMatrix4(camera?.matrixWorldInverse ?? Matrix4());
    ssOrigin.applyMatrix4(projectionMatrix);
    ssOrigin.multiplyScalar(1 / ssOrigin.w);

    // screen space
    ssOrigin.x *= resolution.x / 2;
    ssOrigin.y *= resolution.y / 2;
    ssOrigin.z = 0;

    ssOrigin3.copy(ssOrigin);

    var matrixWorld = this.matrixWorld;
    mvMatrix.multiplyMatrices(camera?.matrixWorldInverse ?? Matrix4(), matrixWorld);

    for (var i = 0, l = instanceStart.count; i < l; i++) {
      start.fromBufferAttribute(instanceStart, i);
      end.fromBufferAttribute(instanceEnd, i);

      start.w = 1;
      end.w = 1;

      // camera space
      start.applyMatrix4(mvMatrix);
      end.applyMatrix4(mvMatrix);

      // clip space
      start.applyMatrix4(projectionMatrix);
      end.applyMatrix4(projectionMatrix);

      // ndc space [ - 1.0, 1.0 ]
      start.multiplyScalar(1 / start.w);
      end.multiplyScalar(1 / end.w);

      // skip the segment if it's outside the camera near and far planes
      var isBehindCameraNear = start.z < -1 && end.z < -1;
      var isPastCameraFar = start.z > 1 && end.z > 1;
      if (isBehindCameraNear || isPastCameraFar) {
        continue;
      }

      // screen space
      start.x *= resolution.x / 2;
      start.y *= resolution.y / 2;

      end.x *= resolution.x / 2;
      end.y *= resolution.y / 2;

      // create 2d segment
      line.start.copy(start);
      line.start.z = 0;

      line.end.copy(end);
      line.end.z = 0;

      // get closest point on ray to segment
      var param = line.closestPointToPointParameter(ssOrigin3, true);
      line.at(param, closestPoint);

      // check if the intersection point is within clip space
      var zPos = MathUtils.lerp(start.z, end.z, param);
      var isInClipSpace = zPos >= -1 && zPos <= 1;

      var isInside = ssOrigin3.distanceTo(closestPoint) < lineWidth * 0.5;

      if (isInClipSpace && isInside) {
        line.start.fromBufferAttribute(instanceStart, i);
        line.end.fromBufferAttribute(instanceEnd, i);

        line.start.applyMatrix4(matrixWorld);
        line.end.applyMatrix4(matrixWorld);

        var pointOnLine = Vector3.init();
        var point = Vector3.init();

        ray.distanceSqToSegment(line.start, line.end, point, pointOnLine);

        intersects.add(Intersection({
          "point": point,
          "pointOnLine": pointOnLine,
          "distance": ray.origin.distanceTo(point),
          "object": this,
          "face": null,
          "faceIndex": i,
          "uv": null,
          "uv2": null,
        }));
      }
    }
  }
}
