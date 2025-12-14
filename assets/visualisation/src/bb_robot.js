// SPDX-FileCopyrightText: 2025 James Harton
//
// SPDX-License-Identifier: Apache-2.0

/**
 * BB Robot classes for Three.js visualisation.
 * Adapted from https://github.com/gkjohnson/urdf-loaders
 */

import * as THREE from 'three';

/**
 * Represents a link (rigid body) in the robot.
 * Contains visual geometry as children.
 */
export class BBLink extends THREE.Object3D {
  constructor(name) {
    super();
    this.name = name;
    this.type = 'BBLink';
    this.isLink = true;
  }
}

/**
 * Joint types supported by BB robots.
 */
export const JointType = {
  FIXED: 'fixed',
  REVOLUTE: 'revolute',
  CONTINUOUS: 'continuous',
  PRISMATIC: 'prismatic',
  FLOATING: 'floating',
  PLANAR: 'planar',
};

/**
 * Represents a joint connecting two links.
 * Handles transforms based on joint type and value.
 */
export class BBJoint extends THREE.Object3D {
  constructor(name, jointType, axis, limits) {
    super();
    this.name = name;
    this.type = 'BBJoint';
    this.isJoint = true;

    this.jointType = jointType;
    this.axis = axis ? new THREE.Vector3(axis.x, axis.y, axis.z) : new THREE.Vector3(0, 0, 1);
    this.limits = limits || { lower: -Math.PI, upper: Math.PI };

    this.jointValue = 0;

    // Store original transform for applying joint values
    this.origPosition = new THREE.Vector3();
    this.origQuaternion = new THREE.Quaternion();
  }

  /**
   * Call after setting initial position/quaternion to store the base transform.
   */
  storeOriginalTransform() {
    this.origPosition.copy(this.position);
    this.origQuaternion.copy(this.quaternion);
  }

  /**
   * Set the joint value (angle in radians for revolute, distance for prismatic).
   * Clamps to limits for revolute/prismatic joints.
   */
  setJointValue(value) {
    if (this.jointType === JointType.FIXED) {
      return false;
    }

    // Clamp value to limits for non-continuous joints
    let clampedValue = value;
    if (this.jointType === JointType.REVOLUTE || this.jointType === JointType.PRISMATIC) {
      if (this.limits) {
        clampedValue = Math.max(this.limits.lower, Math.min(this.limits.upper, value));
      }
    }

    if (this.jointValue === clampedValue) {
      return false;
    }

    this.jointValue = clampedValue;
    this._applyTransform();
    return true;
  }

  /**
   * Apply the joint transform based on type and current value.
   */
  _applyTransform() {
    switch (this.jointType) {
      case JointType.REVOLUTE:
      case JointType.CONTINUOUS:
        // Rotate around axis
        const quat = new THREE.Quaternion();
        quat.setFromAxisAngle(this.axis, this.jointValue);
        this.quaternion.copy(this.origQuaternion).multiply(quat);
        break;

      case JointType.PRISMATIC:
        // Translate along axis
        this.position.copy(this.origPosition);
        this.position.addScaledVector(this.axis, this.jointValue);
        break;

      case JointType.FIXED:
      default:
        // No transform
        break;
    }

    this.updateMatrixWorld(true);
  }
}

/**
 * The root robot object containing all links and joints.
 * Provides dictionary access to joints and links by name.
 */
export class BBRobot extends THREE.Object3D {
  constructor(name) {
    super();
    this.name = name;
    this.type = 'BBRobot';
    this.isRobot = true;

    // Dictionaries for quick access
    this.links = {};
    this.joints = {};
  }

  /**
   * Register a link in the robot.
   */
  addLink(link) {
    this.links[link.name] = link;
  }

  /**
   * Register a joint in the robot.
   */
  addJoint(joint) {
    this.joints[joint.name] = joint;
  }

  /**
   * Set a single joint value by name.
   */
  setJointValue(name, value) {
    const joint = this.joints[name];
    if (joint) {
      return joint.setJointValue(value);
    }
    return false;
  }

  /**
   * Set multiple joint values at once.
   * @param {Object} values - Map of joint name to value
   */
  setJointValues(values) {
    let changed = false;
    for (const [name, value] of Object.entries(values)) {
      if (this.setJointValue(name, value)) {
        changed = true;
      }
    }
    return changed;
  }

  /**
   * Get all current joint values.
   * @returns {Object} Map of joint name to current value
   */
  getJointValues() {
    const values = {};
    for (const [name, joint] of Object.entries(this.joints)) {
      values[name] = joint.jointValue;
    }
    return values;
  }
}
