// SPDX-FileCopyrightText: 2025 James Harton
//
// SPDX-License-Identifier: Apache-2.0

/**
 * Scene builder for BB robot visualisation.
 * Constructs Three.js scene graph from BB robot topology JSON.
 */

import * as THREE from 'three';
import { BBRobot, BBLink, BBJoint, JointType } from './bb_robot.js';
import { createGeometry, applyOrigin } from './geometry_loader.js';

/**
 * Build a BBRobot from BB topology data.
 *
 * @param {Object} topology - Robot topology from Elixir
 * @param {Object} positions - Initial joint positions
 * @returns {BBRobot} The constructed robot
 */
export function buildRobot(topology, positions = {}) {
  const robot = new BBRobot(topology.name || 'robot');

  // Create all links first
  const linkObjects = {};
  for (const [name, linkData] of Object.entries(topology.links || {})) {
    const link = createLink(name, linkData);
    linkObjects[name] = link;
    robot.addLink(link);
  }

  // Create joints and build hierarchy
  for (const [name, jointData] of Object.entries(topology.joints || {})) {
    const joint = createJoint(name, jointData);
    robot.addJoint(joint);

    // Get parent and child links
    const parentLink = linkObjects[jointData.parent];
    const childLink = linkObjects[jointData.child];

    if (parentLink && childLink) {
      // Joint is child of parent link
      parentLink.add(joint);
      // Child link is child of joint
      joint.add(childLink);
    }
  }

  // Find root link (link with no parent joint)
  const childLinks = new Set(
    Object.values(topology.joints || {}).map((j) => j.child)
  );
  const rootLinkName = Object.keys(topology.links || {}).find(
    (name) => !childLinks.has(name)
  );

  if (rootLinkName && linkObjects[rootLinkName]) {
    robot.add(linkObjects[rootLinkName]);
  }

  // Store original transforms for all joints
  for (const joint of Object.values(robot.joints)) {
    joint.storeOriginalTransform();
  }

  // Apply initial positions
  robot.setJointValues(positions);

  return robot;
}

/**
 * Create a BBLink from link data.
 */
function createLink(name, linkData) {
  const link = new BBLink(name);

  // Add visual geometries
  if (linkData.visuals && Array.isArray(linkData.visuals)) {
    for (const visual of linkData.visuals) {
      const visualGroup = createVisual(visual);
      link.add(visualGroup);
    }
  } else if (linkData.visual) {
    // Single visual (older format)
    const visualGroup = createVisual(linkData.visual);
    link.add(visualGroup);
  }

  return link;
}

/**
 * Create a visual group with geometry and transform.
 */
function createVisual(visualData) {
  const group = new THREE.Group();
  group.name = visualData.name || 'visual';

  if (visualData.geometry) {
    const mesh = createGeometry(visualData.geometry, visualData.material);
    group.add(mesh);
  }

  // Apply visual origin transform
  applyOrigin(group, visualData.origin);

  return group;
}

/**
 * Create a BBJoint from joint data.
 */
function createJoint(name, jointData) {
  const jointType = mapJointType(jointData.type);

  // Parse axis (default to Z axis)
  const axis = jointData.axis || { x: 0, y: 0, z: 1 };

  // Parse limits
  const limits = jointData.limits
    ? {
        lower: jointData.limits.lower ?? -Math.PI,
        upper: jointData.limits.upper ?? Math.PI,
      }
    : null;

  const joint = new BBJoint(name, jointType, axis, limits);

  // Apply joint origin transform
  if (jointData.origin) {
    if (jointData.origin.xyz) {
      joint.position.set(
        jointData.origin.xyz.x || 0,
        jointData.origin.xyz.y || 0,
        jointData.origin.xyz.z || 0
      );
    }
    if (jointData.origin.rpy) {
      const euler = new THREE.Euler(
        jointData.origin.rpy.r || 0,
        jointData.origin.rpy.p || 0,
        jointData.origin.rpy.y || 0,
        'XYZ'
      );
      joint.quaternion.setFromEuler(euler);
    }
  }

  return joint;
}

/**
 * Map BB joint type string to JointType enum.
 */
function mapJointType(type) {
  switch (type) {
    case 'revolute':
      return JointType.REVOLUTE;
    case 'continuous':
      return JointType.CONTINUOUS;
    case 'prismatic':
      return JointType.PRISMATIC;
    case 'floating':
      return JointType.FLOATING;
    case 'planar':
      return JointType.PLANAR;
    case 'fixed':
    default:
      return JointType.FIXED;
  }
}

/**
 * Create a default scene with lighting for the robot.
 *
 * @param {THREE.WebGLRenderer} renderer - The renderer
 * @returns {Object} { scene, camera }
 */
export function createScene(width, height) {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xf5f5f5);

  // Add grid helper - rotate from XZ plane (Y-up default) to XY plane (Z-up)
  const gridHelper = new THREE.GridHelper(2, 20, 0xcccccc, 0xe0e0e0);
  gridHelper.rotation.x = Math.PI / 2;
  scene.add(gridHelper);

  // Add axis helper
  const axisHelper = new THREE.AxesHelper(0.5);
  scene.add(axisHelper);

  // Ambient light
  const ambientLight = new THREE.AmbientLight(0x404040, 1);
  scene.add(ambientLight);

  // Directional light (sun-like)
  const directionalLight = new THREE.DirectionalLight(0xffffff, 1);
  directionalLight.position.set(5, 5, 5);
  directionalLight.castShadow = true;
  scene.add(directionalLight);

  // Secondary directional light for fill
  const fillLight = new THREE.DirectionalLight(0xffffff, 0.5);
  fillLight.position.set(-3, 3, -3);
  scene.add(fillLight);

  // Camera - positioned for Z-up view
  const camera = new THREE.PerspectiveCamera(50, width / height, 0.01, 100);
  camera.position.set(1, -1, 0.8);
  camera.up.set(0, 0, 1);
  camera.lookAt(0, 0, 0);

  return { scene, camera };
}
