import 'package:three_dart_flutterflow/three_dart.dart';

// module scope helper variables

class OBBC {
  late Vector3 c;
  late List<Vector3> u;
  late List e;
  OBBC(Map<String, dynamic> json) {
    c = json["c"];
    u = json["u"];
    e = json["e"];
  }
}

var a = OBBC({
  "c": null, // center
  "u": [Vector3.init(), Vector3.init(), Vector3.init()], // basis vectors
  "e": [] // half width
});

var b = OBBC({
  "c": null, // center
  "u": [Vector3.init(), Vector3.init(), Vector3.init()], // basis vectors
  "e": [] // half width
});

var R = [[], [], []];
var absR = [[], [], []];
var t = [];

var xAxis = Vector3.init();
var yAxis = Vector3.init();
var zAxis = Vector3.init();
var v1 = Vector3.init();
var size = Vector3.init();
var closestPoint = Vector3.init();
var rotationMatrix = Matrix3();
var aabb = Box3(null, null);
var obbmatrix = Matrix4();
var inverse = Matrix4();
var localRay = Ray(null, null);

var obb = OBB();
// OBB

class OBB {
  late Vector3 center;
  late Vector3 halfSize;
  late Matrix3 rotation;

  OBB({center, halfSize, rotation}) {
    this.center = center ?? Vector3.init();
    this.halfSize = halfSize ?? Vector3.init();
    this.rotation = rotation ?? Matrix3();
  }

  set(center, halfSize, rotation) {
    this.center = center;
    this.halfSize = halfSize;
    this.rotation = rotation;

    return this;
  }

  copy(obb) {
    center.copy(obb.center);
    halfSize.copy(obb.halfSize);
    rotation.copy(obb.rotation);

    return this;
  }

  clone() {
    return OBB().copy(this);
  }

  getSize(result) {
    return result.copy(halfSize).multiplyScalar(2);
  }

  /// Reference: Closest Point on OBB to Point in Real-Time Collision Detection
  /// by Christer Ericson (chapter 5.1.4)
  clampPoint(point, result) {
    var halfSize = this.halfSize;

    v1.subVectors(point, center);
    rotation.extractBasis(xAxis, yAxis, zAxis);

    // start at the center position of the OBB

    result.copy(center);

    // project the target onto the OBB axes and walk towards that point

    var x = MathUtils.clamp(v1.dot(xAxis), -halfSize.x, halfSize.x);
    result.add(xAxis.multiplyScalar(x));

    var y = MathUtils.clamp(v1.dot(yAxis), -halfSize.y, halfSize.y);
    result.add(yAxis.multiplyScalar(y));

    var z = MathUtils.clamp(v1.dot(zAxis), -halfSize.z, halfSize.z);
    result.add(zAxis.multiplyScalar(z));

    return result;
  }

  containsPoint(point) {
    v1.subVectors(point, center);
    rotation.extractBasis(xAxis, yAxis, zAxis);

    // project v1 onto each axis and check if these points lie inside the OBB

    return Math.abs(v1.dot(xAxis)) <= halfSize.x &&
        Math.abs(v1.dot(yAxis)) <= halfSize.y &&
        Math.abs(v1.dot(zAxis)) <= halfSize.z;
  }

  intersectsBox3(box3) {
    return intersectsOBB(obb.fromBox3(box3));
  }

  intersectsSphere(sphere) {
    // find the point on the OBB closest to the sphere center

    clampPoint(sphere.center, closestPoint);

    // if that point is inside the sphere, the OBB and sphere intersect

    return closestPoint.distanceToSquared(sphere.center) <= (sphere.radius * sphere.radius);
  }

  /// Reference: OBB-OBB Intersection in Real-Time Collision Detection
  /// by Christer Ericson (chapter 4.4.1)
  ///
  intersectsOBB(obb, {epsilon = Math.epsilon}) {
    // prepare data structures (the code uses the same nomenclature like the reference)

    a.c = center;
    a.e[0] = halfSize.x;
    a.e[1] = halfSize.y;
    a.e[2] = halfSize.z;
    rotation.extractBasis(a.u[0], a.u[1], a.u[2]);

    b.c = obb.center;
    b.e[0] = obb.halfSize.x;
    b.e[1] = obb.halfSize.y;
    b.e[2] = obb.halfSize.z;
    obb.rotation.extractBasis(b.u[0], b.u[1], b.u[2]);

    // compute rotation matrix expressing b in a's coordinate frame

    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        R[i][j] = a.u[i].dot(b.u[j]);
      }
    }

    // compute translation vector

    v1.subVectors(b.c, a.c);

    // bring translation into a's coordinate frame

    t[0] = v1.dot(a.u[0]);
    t[1] = v1.dot(a.u[1]);
    t[2] = v1.dot(a.u[2]);

    // compute common subexpressions. Add in an epsilon term to
    // counteract arithmetic errors when two edges are parallel and
    // their cross product is (near) null

    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        absR[i][j] = Math.abs(R[i][j]) + epsilon;
      }
    }

    var ra, rb;

    // test axes L = A0, L = A1, L = A2

    for (var i = 0; i < 3; i++) {
      ra = a.e[i];
      rb = b.e[0] * absR[i][0] + b.e[1] * absR[i][1] + b.e[2] * absR[i][2];
      if (Math.abs(t[i]) > ra + rb) return false;
    }

    // test axes L = B0, L = B1, L = B2

    for (var i = 0; i < 3; i++) {
      ra = a.e[0] * absR[0][i] + a.e[1] * absR[1][i] + a.e[2] * absR[2][i];
      rb = b.e[i];
      if (Math.abs(t[0] * R[0][i] + t[1] * R[1][i] + t[2] * R[2][i]) > ra + rb) return false;
    }

    // test axis L = A0 x B0

    ra = a.e[1] * absR[2][0] + a.e[2] * absR[1][0];
    rb = b.e[1] * absR[0][2] + b.e[2] * absR[0][1];
    if (Math.abs(t[2] * R[1][0] - t[1] * R[2][0]) > ra + rb) return false;

    // test axis L = A0 x B1

    ra = a.e[1] * absR[2][1] + a.e[2] * absR[1][1];
    rb = b.e[0] * absR[0][2] + b.e[2] * absR[0][0];
    if (Math.abs(t[2] * R[1][1] - t[1] * R[2][1]) > ra + rb) return false;

    // test axis L = A0 x B2

    ra = a.e[1] * absR[2][2] + a.e[2] * absR[1][2];
    rb = b.e[0] * absR[0][1] + b.e[1] * absR[0][0];
    if (Math.abs(t[2] * R[1][2] - t[1] * R[2][2]) > ra + rb) return false;

    // test axis L = A1 x B0

    ra = a.e[0] * absR[2][0] + a.e[2] * absR[0][0];
    rb = b.e[1] * absR[1][2] + b.e[2] * absR[1][1];
    if (Math.abs(t[0] * R[2][0] - t[2] * R[0][0]) > ra + rb) return false;

    // test axis L = A1 x B1

    ra = a.e[0] * absR[2][1] + a.e[2] * absR[0][1];
    rb = b.e[0] * absR[1][2] + b.e[2] * absR[1][0];
    if (Math.abs(t[0] * R[2][1] - t[2] * R[0][1]) > ra + rb) return false;

    // test axis L = A1 x B2

    ra = a.e[0] * absR[2][2] + a.e[2] * absR[0][2];
    rb = b.e[0] * absR[1][1] + b.e[1] * absR[1][0];
    if (Math.abs(t[0] * R[2][2] - t[2] * R[0][2]) > ra + rb) return false;

    // test axis L = A2 x B0

    ra = a.e[0] * absR[1][0] + a.e[1] * absR[0][0];
    rb = b.e[1] * absR[2][2] + b.e[2] * absR[2][1];
    if (Math.abs(t[1] * R[0][0] - t[0] * R[1][0]) > ra + rb) return false;

    // test axis L = A2 x B1

    ra = a.e[0] * absR[1][1] + a.e[1] * absR[0][1];
    rb = b.e[0] * absR[2][2] + b.e[2] * absR[2][0];
    if (Math.abs(t[1] * R[0][1] - t[0] * R[1][1]) > ra + rb) return false;

    // test axis L = A2 x B2

    ra = a.e[0] * absR[1][2] + a.e[1] * absR[0][2];
    rb = b.e[0] * absR[2][1] + b.e[1] * absR[2][0];
    if (Math.abs(t[1] * R[0][2] - t[0] * R[1][2]) > ra + rb) return false;

    // since no separating axis is found, the OBBs must be intersecting

    return true;
  }

  /// Reference: Testing Box Against Plane in Real-Time Collision Detection
  /// by Christer Ericson (chapter 5.2.3)
  intersectsPlane(plane) {
    rotation.extractBasis(xAxis, yAxis, zAxis);

    // compute the projection interval radius of this OBB onto L(t) = this->center + t * p.normal;

    var r = halfSize.x * Math.abs(plane.normal.dot(xAxis)) +
        halfSize.y * Math.abs(plane.normal.dot(yAxis)) +
        halfSize.z * Math.abs(plane.normal.dot(zAxis));

    // compute distance of the OBB's center from the plane

    var d = plane.normal.dot(center) - plane.constant;

    // Intersection occurs when distance d falls within [-r,+r] interval

    return Math.abs(d) <= r;
  }

  /// Performs a ray/OBB intersection test and stores the intersection point
  /// to the given 3D vector. If no intersection is detected, *null* is returned.
  intersectRay(ray, result) {
    // the idea is to perform the intersection test in the local space
    // of the OBB.

    getSize(size);
    aabb.setFromCenterAndSize(v1.set(0, 0, 0), size);

    // create a 4x4 transformation matrix

    matrix4FromRotationMatrix(obbmatrix, rotation);
    obbmatrix.setPositionFromVector3(center);

    // transform ray to the local space of the OBB

    inverse.copy(obbmatrix).invert();
    localRay.copy(ray).applyMatrix4(inverse);

    // perform ray <-> AABB intersection test

    if (localRay.intersectBox(aabb, result) != null) {
      // transform the intersection point back to world space

      return result.applyMatrix4(obbmatrix);
    } else {
      return null;
    }
  }

  /// Performs a ray/OBB intersection test. Returns either true or false if
  /// there is a intersection or not.
  intersectsRay(ray) {
    return intersectRay(ray, v1) != null;
  }

  fromBox3(box3) {
    box3.getCenter(center);

    box3.getSize(halfSize).multiplyScalar(0.5);

    rotation.identity();

    return this;
  }

  equals(obb) {
    return obb.center.equals(center) && obb.halfSize.equals(halfSize) && obb.rotation.equals(rotation);
  }

  applyMatrix4(matrix) {
    var e = matrix.elements;

    var sx = v1.set(e[0], e[1], e[2]).length();
    var sy = v1.set(e[4], e[5], e[6]).length();
    var sz = v1.set(e[8], e[9], e[10]).length();

    var det = matrix.determinant();
    if (det < 0) sx = -sx;

    rotationMatrix.setFromMatrix4(matrix);

    var invSX = 1 / sx;
    var invSY = 1 / sy;
    var invSZ = 1 / sz;

    rotationMatrix.elements[0] *= invSX;
    rotationMatrix.elements[1] *= invSX;
    rotationMatrix.elements[2] *= invSX;

    rotationMatrix.elements[3] *= invSY;
    rotationMatrix.elements[4] *= invSY;
    rotationMatrix.elements[5] *= invSY;

    rotationMatrix.elements[6] *= invSZ;
    rotationMatrix.elements[7] *= invSZ;
    rotationMatrix.elements[8] *= invSZ;

    rotation.multiply(rotationMatrix);

    halfSize.x *= sx;
    halfSize.y *= sy;
    halfSize.z *= sz;

    v1.setFromMatrixPosition(matrix);
    center.add(v1);

    return this;
  }
}

matrix4FromRotationMatrix(matrix4, matrix3) {
  var e = matrix4.elements;
  var me = matrix3.elements;

  e[0] = me[0];
  e[1] = me[1];
  e[2] = me[2];
  e[3] = 0;

  e[4] = me[3];
  e[5] = me[4];
  e[6] = me[5];
  e[7] = 0;

  e[8] = me[6];
  e[9] = me[7];
  e[10] = me[8];
  e[11] = 0;

  e[12] = 0;
  e[13] = 0;
  e[14] = 0;
  e[15] = 1;
}
