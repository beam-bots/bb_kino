/**
 * BB Kino Visualisation - Main entry point
 *
 * Integrates Three.js robot visualisation with Kino.JS.Live
 */

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { buildRobot, createScene } from './scene_builder.js';

/**
 * Initialize the visualisation widget.
 * Called by Kino.JS.Live when the widget connects.
 */
export function init(ctx, payload) {
  if (payload.error) {
    ctx.root.innerHTML = `<div class="bb-vis bb-vis-error">
      <span class="error-message">${payload.error}</span>
    </div>`;
    return;
  }

  // Create container
  ctx.root.innerHTML = `
    <div class="bb-vis">
      <div class="vis-header">
        <span class="title">${payload.name || 'Robot Visualisation'}</span>
        <div class="vis-controls">
          <button class="reset-view-btn" title="Reset camera view">Reset View</button>
        </div>
      </div>
      <div class="vis-container"></div>
    </div>
  `;

  const container = ctx.root.querySelector('.vis-container');
  const resetViewBtn = ctx.root.querySelector('.reset-view-btn');

  // Get dimensions
  const width = container.clientWidth || 600;
  const height = 400;

  // Create renderer
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(width, height);
  renderer.setPixelRatio(window.devicePixelRatio);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  container.appendChild(renderer.domElement);

  // Create scene and camera (camera.up is set to Z in createScene)
  const { scene, camera } = createScene(width, height);

  // IMPORTANT: camera.up must be set BEFORE creating OrbitControls
  // as the controls cache the up vector on construction
  camera.up.set(0, 0, 1);

  // Add orbit controls - Z-up orientation
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.05;
  controls.target.set(0, 0, 0);
  controls.update();

  // Build robot from topology
  let robot = null;
  if (payload.topology) {
    robot = buildRobot(payload.topology, payload.positions || {});
    scene.add(robot);

    // Auto-frame the robot
    frameRobot(camera, controls, robot);
  }

  // Store initial camera position for reset
  const initialCameraPosition = camera.position.clone();
  const initialControlsTarget = controls.target.clone();

  // Reset view button
  resetViewBtn.addEventListener('click', () => {
    camera.position.copy(initialCameraPosition);
    controls.target.copy(initialControlsTarget);
    controls.update();
  });

  // Animation loop
  let animationId = null;

  function animate() {
    animationId = requestAnimationFrame(animate);
    controls.update();
    renderer.render(scene, camera);
  }

  animate();

  // Handle position updates from server
  ctx.handleEvent('positions_updated', ({ positions }) => {
    if (robot && positions) {
      robot.setJointValues(positions);
    }
  });

  // Handle window resize
  const resizeObserver = new ResizeObserver((entries) => {
    for (const entry of entries) {
      const { width: newWidth } = entry.contentRect;
      if (newWidth > 0) {
        const newHeight = 400;
        camera.aspect = newWidth / newHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(newWidth, newHeight);
      }
    }
  });
  resizeObserver.observe(container);

}

/**
 * Auto-frame the camera to fit the robot in view.
 * Uses Z-up coordinate system.
 */
function frameRobot(camera, controls, robot) {
  // Compute bounding box
  const box = new THREE.Box3().setFromObject(robot);
  const center = box.getCenter(new THREE.Vector3());
  const size = box.getSize(new THREE.Vector3());

  // Get the maximum dimension
  const maxDim = Math.max(size.x, size.y, size.z);
  const fov = camera.fov * (Math.PI / 180);
  let cameraDistance = maxDim / (2 * Math.tan(fov / 2));

  // Add some padding
  cameraDistance *= 1.5;

  // Minimum distance
  cameraDistance = Math.max(cameraDistance, 0.5);

  // Position camera for Z-up view (looking from front-right, elevated)
  camera.position.set(
    center.x + cameraDistance * 0.7,
    center.y - cameraDistance * 0.7,
    center.z + cameraDistance * 0.5
  );

  // Ensure Z-up orientation
  camera.up.set(0, 0, 1);

  // Update controls target
  controls.target.copy(center);
  controls.update();
}

// Export for Kino.JS
export default { init };
