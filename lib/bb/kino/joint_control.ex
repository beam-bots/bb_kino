# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.JointControl do
  @moduledoc """
  A Kino widget for controlling robot joint positions.

  Displays a table of all movable joints with:
  - Joint name and type
  - Current position (updated in real-time)
  - Position limits (min/max)
  - Draggable slider for setting target position

  **Safety**: Controls are only enabled when the robot is armed.
  Position commands are not sent when the robot is disarmed.

  ## Usage

      BB.Kino.JointControl.new(MyRobot)

  The widget automatically:
  - Discovers all joints from the robot topology
  - Subscribes to sensor messages for position updates
  - Subscribes to state machine for armed/disarmed state
  - Sends position commands to actuators when slider changes
  """
  use Kino.JS
  use Kino.JS.Live

  alias BB.Kino.Shared.RobotContext
  alias BB.Message
  alias BB.Robot.Runtime, as: RobotRuntime
  alias Kino.JS.Live, as: KinoLive

  @position_throttle_ms 33

  @doc """
  Creates a new joint control widget for the given robot.
  """
  @spec new(module()) :: KinoLive.t()
  def new(robot_module) do
    KinoLive.new(__MODULE__, robot_module)
  end

  @impl true
  def init(robot_module, ctx) do
    case RobotContext.validate_robot(robot_module) do
      {:ok, robot} ->
        robot_struct = RobotRuntime.get_robot(robot)
        positions = RobotRuntime.configurations(robot)
        armed = BB.Safety.armed?(robot)

        joints = build_joint_data(robot_struct, positions)

        BB.subscribe(robot, [:sensor])
        BB.subscribe(robot, [:state_machine])

        {:ok,
         assign(ctx,
           robot: robot,
           robot_struct: robot_struct,
           joints: joints,
           armed: armed,
           pending_positions: %{},
           position_flush_scheduled: false
         )}

      {:error, reason} ->
        {:ok, assign(ctx, error: reason)}
    end
  end

  defp build_joint_data(robot_struct, positions) do
    robot_struct.joints
    |> Enum.filter(fn {_name, joint} -> movable_joint?(joint) end)
    |> Enum.map(fn {name, joint} ->
      actuator = find_actuator_for_joint(robot_struct, name)
      position = Map.get(positions, name, 0.0)

      %{
        name: name,
        type: joint.type,
        position: position,
        lower_limit: get_limit(joint, :lower),
        upper_limit: get_limit(joint, :upper),
        actuator: actuator
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp movable_joint?(joint) do
    joint.type in [:revolute, :continuous, :prismatic]
  end

  defp get_limit(joint, which) do
    case joint.limits do
      nil -> nil
      limits -> Map.get(limits, which)
    end
  end

  defp find_actuator_for_joint(robot_struct, joint_name) do
    robot_struct.actuators
    |> Enum.find(fn {_name, info} -> info.joint == joint_name end)
    |> case do
      {actuator_name, _info} -> actuator_name
      nil -> nil
    end
  end

  @impl true
  def handle_connect(ctx) do
    if ctx.assigns[:error] do
      {:ok, %{error: ctx.assigns.error}, ctx}
    else
      payload = %{
        joints: format_joints_for_client(ctx.assigns.joints),
        armed: ctx.assigns.armed
      }

      {:ok, payload, ctx}
    end
  end

  defp format_joints_for_client(joints) do
    Enum.map(joints, fn joint ->
      %{
        name: Atom.to_string(joint.name),
        type: Atom.to_string(joint.type),
        position: joint.position,
        lower_limit: joint.lower_limit,
        upper_limit: joint.upper_limit,
        has_actuator: joint.actuator != nil
      }
    end)
  end

  @impl true
  def handle_event("set_position", %{"joint" => joint_name, "position" => position}, ctx) do
    ctx = maybe_set_position(ctx, joint_name, position)
    {:noreply, ctx}
  end

  defp maybe_set_position(ctx, _joint_name, _position) when not ctx.assigns.armed, do: ctx

  defp maybe_set_position(ctx, joint_name, position) do
    joint_atom = String.to_existing_atom(joint_name)

    case find_joint(ctx.assigns.joints, joint_atom) do
      nil -> ctx
      %{actuator: nil} -> send_simulated_position(ctx, joint_atom, position)
      joint -> send_position_command_and_return(ctx, joint_atom, joint.actuator, position)
    end
  end

  defp find_joint(joints, name), do: Enum.find(joints, fn j -> j.name == name end)

  defp send_position_command_and_return(ctx, joint_name, actuator, position) do
    send_position_command(ctx.assigns.robot, joint_name, actuator, position)
    ctx
  end

  defp send_position_command(robot, _joint_name, actuator_name, position) do
    BB.Actuator.set_position!(robot, actuator_name, position)
  end

  defp send_simulated_position(ctx, joint_name, position) do
    # Update internal state
    updated_joints =
      Enum.map(ctx.assigns.joints, fn joint ->
        if joint.name == joint_name do
          %{joint | position: position}
        else
          joint
        end
      end)

    # Broadcast position update to all connected clients (including visualisation)
    broadcast_event(ctx, "positions_updated", %{
      positions: [%{name: Atom.to_string(joint_name), position: position}]
    })

    # Also publish to BB PubSub so visualisation widget can receive it
    {:ok, msg} =
      Message.new(BB.Message.Sensor.JointState, :simulated,
        names: [joint_name],
        positions: [position * 1.0],
        velocities: [0.0],
        efforts: [0.0]
      )

    BB.publish(ctx.assigns.robot, [:sensor, :simulated], msg)

    assign(ctx, joints: updated_joints)
  end

  @impl true
  def handle_info({:bb, [:state_machine], %BB.Message{payload: payload}}, ctx) do
    armed = payload.to in [:armed, :idle, :executing]
    broadcast_event(ctx, "armed_changed", %{armed: armed})
    {:noreply, assign(ctx, armed: armed)}
  end

  def handle_info(
        {:bb, [:sensor | _rest], %BB.Message{payload: %BB.Message.Sensor.JointState{} = js}},
        ctx
      ) do
    updates = Enum.zip(js.names, js.positions) |> Map.new()

    updated_joints =
      Enum.map(ctx.assigns.joints, fn joint ->
        case Map.get(updates, joint.name) do
          nil -> joint
          pos -> %{joint | position: pos}
        end
      end)

    # Each joint's estimator publishes its own single-joint JointState. Batch
    # the updates and broadcast them together on a throttled flush, rather than
    # one event per joint per estimator tick.
    ctx =
      ctx
      |> assign(joints: updated_joints)
      |> assign(pending_positions: Map.merge(ctx.assigns.pending_positions, updates))
      |> schedule_position_flush()

    {:noreply, ctx}
  end

  def handle_info(:flush_positions, ctx) do
    position_updates =
      Enum.map(ctx.assigns.pending_positions, fn {name, pos} ->
        %{name: Atom.to_string(name), position: pos}
      end)

    unless position_updates == [] do
      broadcast_event(ctx, "positions_updated", %{positions: position_updates})
    end

    {:noreply, assign(ctx, pending_positions: %{}, position_flush_scheduled: false)}
  end

  def handle_info(_msg, ctx) do
    {:noreply, ctx}
  end

  defp schedule_position_flush(%{assigns: %{position_flush_scheduled: true}} = ctx), do: ctx

  defp schedule_position_flush(ctx) do
    Process.send_after(self(), :flush_positions, @position_throttle_ms)
    assign(ctx, position_flush_scheduled: true)
  end

  @impl true
  def terminate(_reason, ctx) do
    if ctx.assigns[:robot] do
      BB.unsubscribe(ctx.assigns.robot, [:sensor])
      BB.unsubscribe(ctx.assigns.robot, [:state_machine])
    end

    :ok
  end

  asset "main.js" do
    """
    export function init(ctx, payload) {
      ctx.importCSS("main.css");

      if (payload.error) {
        ctx.root.innerHTML = `<div class="bb-joints bb-joints-error">
          <span class="error-message">${payload.error}</span>
        </div>`;
        return;
      }

      ctx.root.innerHTML = `
        <div class="bb-joints">
          <div class="header">
            <span class="title">Joint Control</span>
            <span class="armed-indicator"></span>
          </div>
          <div class="joint-table">
            <div class="table-header">
              <span class="col-name">Joint</span>
              <span class="col-type">Type</span>
              <span class="col-position">Position</span>
              <span class="col-slider">Target</span>
            </div>
            <div class="table-body"></div>
          </div>
        </div>
      `;

      const armedIndicator = ctx.root.querySelector(".armed-indicator");
      const tableBody = ctx.root.querySelector(".table-body");

      let joints = payload.joints || [];
      let armed = payload.armed;
      let activeSlider = null;  // Track which slider is being dragged

      function formatPosition(pos, type) {
        if (pos === null || pos === undefined) return "N/A";
        if (type === "prismatic") {
          return (pos * 1000).toFixed(1) + " mm";
        } else {
          return (pos * 180 / Math.PI).toFixed(1) + "°";
        }
      }

      function formatLimit(limit, type) {
        if (limit === null || limit === undefined) return "∞";
        if (type === "prismatic") {
          return (limit * 1000).toFixed(0);
        } else {
          return (limit * 180 / Math.PI).toFixed(0);
        }
      }

      function updateArmedIndicator() {
        armedIndicator.className = "armed-indicator " + (armed ? "armed" : "disarmed");
        armedIndicator.textContent = armed ? "Armed" : "Disarmed";
      }

      function renderJoints() {
        tableBody.innerHTML = joints.map(joint => {
          const hasLimits = joint.lower_limit !== null && joint.upper_limit !== null;
          const min = hasLimits ? joint.lower_limit : -Math.PI;
          const max = hasLimits ? joint.upper_limit : Math.PI;
          const step = (max - min) / 100;
          const disabled = !armed;
          const isSimulated = !joint.has_actuator;

          return `
            <div class="joint-row ${isSimulated ? 'simulated' : ''}" data-joint="${joint.name}">
              <span class="col-name">${joint.name}${isSimulated ? ' <span class="sim-badge">sim</span>' : ''}</span>
              <span class="col-type">${joint.type}</span>
              <span class="col-position">${formatPosition(joint.position, joint.type)}</span>
              <span class="col-slider">
                <span class="limit-label">${formatLimit(joint.lower_limit, joint.type)}</span>
                <input type="range"
                  class="position-slider"
                  min="${min}"
                  max="${max}"
                  step="${step}"
                  value="${joint.position}"
                  ${disabled ? 'disabled' : ''}
                  title="${isSimulated ? 'Simulation mode (no actuator)' : ''}"
                >
                <span class="limit-label">${formatLimit(joint.upper_limit, joint.type)}</span>
              </span>
            </div>
          `;
        }).join('');

        tableBody.querySelectorAll('.position-slider').forEach(slider => {
          const jointName = slider.closest('.joint-row').dataset.joint;

          slider.addEventListener('focus', () => {
            activeSlider = jointName;
          });

          slider.addEventListener('blur', () => {
            activeSlider = null;
          });

          slider.addEventListener('input', (e) => {
            if (!armed) return;
            activeSlider = jointName;
            const position = parseFloat(e.target.value);
            ctx.pushEvent('set_position', { joint: jointName, position: position });
          });
        });
      }

      updateArmedIndicator();
      renderJoints();

      ctx.handleEvent('armed_changed', ({ armed: a }) => {
        armed = a;
        updateArmedIndicator();
        renderJoints();
      });

      ctx.handleEvent('positions_updated', ({ positions }) => {
        positions.forEach(({ name, position }) => {
          const joint = joints.find(j => j.name === name);
          if (joint) {
            joint.position = position;
            const row = tableBody.querySelector(`[data-joint="${name}"]`);
            if (row) {
              const posCol = row.querySelector('.col-position');
              posCol.textContent = formatPosition(position, joint.type);

              // Update slider value unless user is actively dragging it
              if (activeSlider !== name) {
                const slider = row.querySelector('.position-slider');
                if (slider) {
                  slider.value = position;
                }
              }
            }
          }
        });
      });
    }
    """
  end

  asset "main.css" do
    """
    .bb-joints {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      border: 1px solid #e0e0e0;
      border-radius: 8px;
      background: #fafafa;
      overflow: hidden;
    }

    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 16px;
      background: #f5f5f5;
      border-bottom: 1px solid #e0e0e0;
    }

    .title {
      font-weight: 600;
      font-size: 14px;
      color: #333;
    }

    .armed-indicator {
      font-size: 12px;
      padding: 4px 8px;
      border-radius: 4px;
      font-weight: 500;
    }

    .armed-indicator.armed {
      background: #e8f5e9;
      color: #2e7d32;
    }

    .armed-indicator.disarmed {
      background: #fafafa;
      color: #757575;
      border: 1px solid #e0e0e0;
    }

    .joint-table {
      padding: 8px 0;
    }

    .table-header {
      display: grid;
      grid-template-columns: minmax(80px, 1fr) minmax(60px, 0.6fr) minmax(70px, 0.6fr) minmax(120px, 2fr);
      gap: 8px;
      padding: 8px 12px;
      font-size: 12px;
      font-weight: 600;
      color: #666;
      text-transform: uppercase;
      border-bottom: 1px solid #eee;
    }

    .joint-row {
      display: grid;
      grid-template-columns: minmax(80px, 1fr) minmax(60px, 0.6fr) minmax(70px, 0.6fr) minmax(120px, 2fr);
      gap: 8px;
      padding: 8px 12px;
      align-items: center;
      border-bottom: 1px solid #f5f5f5;
    }

    .joint-row:hover {
      background: #fafafa;
    }

    .col-name {
      font-weight: 500;
      color: #333;
    }

    .sim-badge {
      font-size: 9px;
      background: #fff3e0;
      color: #e65100;
      padding: 2px 4px;
      border-radius: 3px;
      font-weight: 600;
      text-transform: uppercase;
      margin-left: 4px;
    }

    .joint-row.simulated .position-slider {
      accent-color: #ff9800;
    }

    .col-type {
      font-size: 12px;
      color: #888;
    }

    .col-position {
      font-family: monospace;
      font-size: 13px;
      color: #333;
    }

    .col-slider {
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .limit-label {
      font-size: 11px;
      color: #999;
      width: 40px;
      text-align: center;
    }

    .position-slider {
      flex: 1;
      height: 6px;
      cursor: pointer;
    }

    .position-slider:disabled {
      opacity: 0.4;
      cursor: not-allowed;
    }

    .bb-joints-error {
      padding: 16px;
    }

    .error-message {
      color: #c62828;
    }
    """
  end
end
