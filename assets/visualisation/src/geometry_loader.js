/**
 * Geometry loader for BB robot visualisation.
 * Converts BB geometry definitions to Three.js geometry objects.
 */

import * as THREE from 'three';

// Default material for robot visuals
const defaultMaterial = new THREE.MeshPhongMaterial({
  color: 0x888888,
  side: THREE.DoubleSide,
});

/**
 * Create a Three.js mesh from a BB geometry definition.
 *
 * @param {Object} geometry - BB geometry object with type and params
 * @param {Object} material - Optional material definition
 * @returns {THREE.Mesh} The created mesh
 */
export function createGeometry(geometry, material) {
  const threeMaterial = createMaterial(material);
  let threeGeometry;

  switch (geometry.type) {
    case 'box':
      threeGeometry = createBox(geometry);
      break;

    case 'cylinder':
      threeGeometry = createCylinder(geometry);
      break;

    case 'sphere':
      threeGeometry = createSphere(geometry);
      break;

    case 'mesh':
      // For now, create a placeholder box for mesh geometries
      // Full STL/mesh loading would require async loading
      threeGeometry = createMeshPlaceholder(geometry);
      break;

    default:
      console.warn(`Unknown geometry type: ${geometry.type}`);
      threeGeometry = new THREE.BoxGeometry(0.05, 0.05, 0.05);
  }

  const mesh = new THREE.Mesh(threeGeometry, threeMaterial);
  mesh.castShadow = true;
  mesh.receiveShadow = true;

  return mesh;
}

/**
 * Create a box geometry.
 * BB format: { type: "box", x: width, y: height, z: depth }
 */
function createBox(geometry) {
  const x = geometry.x || 0.1;
  const y = geometry.y || 0.1;
  const z = geometry.z || 0.1;
  return new THREE.BoxGeometry(x, y, z);
}

/**
 * Create a cylinder geometry.
 * BB format: { type: "cylinder", radius: r, length: l }
 *
 * Note: Three.js cylinders are oriented along Y axis by default,
 * but URDF/BB uses Z axis. We rotate the geometry to match.
 */
function createCylinder(geometry) {
  const radius = geometry.radius || 0.05;
  const length = geometry.length || 0.1;
  const segments = 32;

  const geo = new THREE.CylinderGeometry(radius, radius, length, segments);
  // Rotate to align with Z axis (BB/URDF convention)
  geo.rotateX(Math.PI / 2);
  return geo;
}

/**
 * Create a sphere geometry.
 * BB format: { type: "sphere", radius: r }
 */
function createSphere(geometry) {
  const radius = geometry.radius || 0.05;
  return new THREE.SphereGeometry(radius, 32, 16);
}

/**
 * Create a placeholder for mesh geometries.
 * In the future, this could load STL/DAE/GLTF files.
 * BB format: { type: "mesh", filename: "path/to/mesh.stl", scale: { x, y, z } }
 */
function createMeshPlaceholder(geometry) {
  // Use a small box as placeholder
  const scale = geometry.scale || { x: 1, y: 1, z: 1 };
  return new THREE.BoxGeometry(0.1 * scale.x, 0.1 * scale.y, 0.1 * scale.z);
}

/**
 * Create a Three.js material from BB material definition.
 *
 * @param {Object} material - BB material object
 * @returns {THREE.Material} The created material
 */
function createMaterial(material) {
  if (!material) {
    return defaultMaterial.clone();
  }

  const params = {
    side: THREE.DoubleSide,
  };

  // Handle colour (British spelling from BB, but also support American)
  const colour = material.colour || material.color;
  if (colour) {
    if (typeof colour === 'string') {
      params.color = new THREE.Color(colour);
    } else if (colour.r !== undefined) {
      params.color = new THREE.Color(colour.r, colour.g, colour.b);
    } else if (colour.rgba) {
      params.color = new THREE.Color(colour.rgba.r, colour.rgba.g, colour.rgba.b);
      if (colour.rgba.a !== undefined && colour.rgba.a < 1) {
        params.transparent = true;
        params.opacity = colour.rgba.a;
      }
    }
  }

  return new THREE.MeshPhongMaterial(params);
}

/**
 * Apply origin transform to a visual mesh.
 *
 * @param {THREE.Object3D} object - The object to transform
 * @param {Object} origin - Origin with xyz position and rpy rotation
 */
export function applyOrigin(object, origin) {
  if (!origin) return;

  // Apply position
  if (origin.xyz) {
    object.position.set(
      origin.xyz.x || 0,
      origin.xyz.y || 0,
      origin.xyz.z || 0
    );
  }

  // Apply rotation (roll-pitch-yaw in radians)
  if (origin.rpy) {
    const euler = new THREE.Euler(
      origin.rpy.r || 0,
      origin.rpy.p || 0,
      origin.rpy.y || 0,
      'XYZ'
    );
    object.quaternion.setFromEuler(euler);
  }
}
