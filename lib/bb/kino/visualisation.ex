# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Visualisation do
  @moduledoc """
  A Kino widget for 3D robot visualisation using Three.js.

  Displays an interactive 3D view of the robot with:
  - Real-time joint position updates
  - Orbit camera controls (pan, zoom, rotate)
  - Visual geometry rendering (boxes, cylinders, spheres)

  ## Usage

      BB.Kino.Visualisation.new(MyRobot)

  The widget automatically:
  - Loads the robot topology and geometry
  - Subscribes to sensor messages for position updates
  - Updates joint transforms in real-time
  """
  use Kino.JS
  use Kino.JS.Live

  alias BB.Kino.Shared.RobotContext
  alias BB.Math.Quaternion
  alias BB.Math.Transform
  alias BB.Math.Transform2D
  alias BB.Math.Vec3
  alias BB.Robot.Runtime, as: RobotRuntime
  alias Kino.JS.Live, as: KinoLive

  @position_throttle_ms 33

  @doc """
  Creates a new 3D visualisation widget for the given robot.
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

        BB.subscribe(robot, [:sensor])

        {:ok,
         assign(ctx,
           robot: robot,
           robot_struct: robot_struct,
           positions: positions,
           position_flush_scheduled: false
         )}

      {:error, reason} ->
        {:ok, assign(ctx, error: reason)}
    end
  end

  @impl true
  def handle_connect(ctx) do
    if ctx.assigns[:error] do
      {:ok, %{error: ctx.assigns.error}, ctx}
    else
      topology = serialize_topology(ctx.assigns.robot_struct)
      positions = serialize_positions(ctx.assigns.positions, ctx.assigns.robot_struct)

      payload = %{
        topology: topology,
        positions: positions
      }

      {:ok, payload, ctx}
    end
  end

  @impl true
  def handle_info(
        {:bb, [:sensor | _rest], %BB.Message{payload: %BB.Message.Sensor.JointState{} = js}},
        ctx
      ) do
    # Each joint's estimator publishes its own single-joint JointState on its
    # own topic. Merge updates into a running pose and broadcast the complete
    # pose on a throttled flush, rather than emitting one joint per message
    # (which floods the transport and never carries a full pose).
    updates = Enum.zip(js.names, js.positions) |> Map.new()

    ctx =
      ctx
      |> assign(positions: Map.merge(ctx.assigns.positions, updates))
      |> schedule_position_flush()

    {:noreply, ctx}
  end

  def handle_info(:flush_positions, ctx) do
    broadcast_event(ctx, "positions_updated", %{
      positions: serialize_positions(ctx.assigns.positions, ctx.assigns.robot_struct)
    })

    {:noreply, assign(ctx, position_flush_scheduled: false)}
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
    end

    :ok
  end

  # Serialization helpers

  defp serialize_topology(robot_struct) do
    %{
      name: Atom.to_string(robot_struct.name),
      links: serialize_links(robot_struct.links),
      joints: serialize_joints(robot_struct.joints)
    }
  end

  defp serialize_links(links) do
    links
    |> Enum.map(fn {name, link} ->
      {Atom.to_string(name), serialize_link(link)}
    end)
    |> Map.new()
  end

  defp serialize_link(link) do
    %{
      name: Atom.to_string(link.name),
      visual: serialize_visual(link.visual)
    }
  end

  defp serialize_visual(nil), do: nil

  defp serialize_visual(visual) do
    %{
      origin: serialize_origin(visual.origin),
      geometry: serialize_geometry(visual.geometry),
      material: serialize_material(visual.material)
    }
  end

  defp serialize_origin(nil), do: nil

  defp serialize_origin({position, orientation}) do
    {px, py, pz} = position
    {r, p, y} = orientation

    %{
      xyz: %{x: px, y: py, z: pz},
      rpy: %{r: r, p: p, y: y}
    }
  end

  defp serialize_geometry(nil), do: nil

  defp serialize_geometry({:box, dims}) do
    %{type: "box", x: dims.x, y: dims.y, z: dims.z}
  end

  defp serialize_geometry({:cylinder, dims}) do
    %{type: "cylinder", radius: dims.radius, length: dims[:height] || dims[:length]}
  end

  defp serialize_geometry({:sphere, dims}) do
    %{type: "sphere", radius: dims.radius}
  end

  defp serialize_geometry({:mesh, info}) do
    %{
      type: "mesh",
      filename: info.filename,
      scale: serialize_scale(info[:scale])
    }
  end

  defp serialize_scale(nil), do: %{x: 1, y: 1, z: 1}
  defp serialize_scale(scale) when is_number(scale), do: %{x: scale, y: scale, z: scale}
  defp serialize_scale({x, y, z}), do: %{x: x, y: y, z: z}
  defp serialize_scale(%{x: x, y: y, z: z}), do: %{x: x, y: y, z: z}

  defp serialize_material(nil), do: nil

  defp serialize_material(material) do
    %{
      name: material[:name] && Atom.to_string(material.name),
      colour: serialize_colour(material[:color])
    }
  end

  defp serialize_colour(nil), do: nil

  defp serialize_colour(%{red: r, green: g, blue: b, alpha: a}),
    do: %{rgba: %{r: r, g: g, b: b, a: a}}

  defp serialize_colour({r, g, b, a}), do: %{rgba: %{r: r, g: g, b: b, a: a}}
  defp serialize_colour({r, g, b}), do: %{r: r, g: g, b: b}

  defp serialize_joints(joints) do
    joints
    |> Enum.map(fn {name, joint} ->
      {Atom.to_string(name), serialize_joint(joint)}
    end)
    |> Map.new()
  end

  defp serialize_joint(joint) do
    %{
      name: Atom.to_string(joint.name),
      type: Atom.to_string(joint.type),
      parent: Atom.to_string(joint.parent_link),
      child: Atom.to_string(joint.child_link),
      origin: serialize_joint_origin(joint.origin),
      axis: serialize_axis(joint.axis),
      limits: serialize_limits(joint.limits)
    }
  end

  defp serialize_joint_origin(nil), do: nil

  defp serialize_joint_origin(origin) do
    {px, py, pz} = origin.position
    {r, p, y} = origin.orientation

    %{
      xyz: %{x: px, y: py, z: pz},
      rpy: %{r: r, p: p, y: y}
    }
  end

  defp serialize_axis(nil), do: %{x: 0, y: 0, z: 1}
  defp serialize_axis({x, y, z}), do: %{x: x, y: y, z: z}

  defp serialize_limits(nil), do: nil

  defp serialize_limits(limits) do
    %{
      lower: limits[:lower],
      upper: limits[:upper]
    }
  end

  defp serialize_positions(positions, robot_struct) do
    Map.new(positions, fn {name, configuration} ->
      {Atom.to_string(name), serialize_configuration(configuration, robot_struct.joints[name])}
    end)
  end

  defp serialize_configuration(configuration, _joint) when is_number(configuration),
    do: configuration

  # A planar configuration only means anything alongside the plane normal it was
  # measured against, and a floating one is already a full pose. Lifting the
  # planar case here — through the same `Transform2D.to_transform/2` forward
  # kinematics uses — keeps the plane basis convention in `bb`, and leaves the
  # browser a pose it can apply without knowing about either.
  defp serialize_configuration(%Transform2D{} = configuration, joint) do
    configuration
    |> Transform2D.to_transform(plane_normal(joint))
    |> serialize_pose()
  end

  defp serialize_configuration(%Transform{} = configuration, _joint),
    do: serialize_pose(configuration)

  defp plane_normal(%{axis: {x, y, z}}), do: Vec3.new(x, y, z)
  defp plane_normal(_joint), do: Vec3.unit_z()

  defp serialize_pose(transform) do
    [x, y, z] = transform |> Transform.get_translation() |> Vec3.to_list()
    [qx, qy, qz, qw] = transform |> Transform.get_quaternion() |> Quaternion.to_xyzw_list()

    %{
      xyz: %{x: x, y: y, z: z},
      quat: %{x: qx, y: qy, z: qz, w: qw}
    }
  end

  asset "main.js" do
    File.read!(Path.join([__DIR__, "..", "..", "..", "priv", "static", "visualisation.js"]))
  end

  asset "main.css" do
    """
    .bb-vis {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      border: 1px solid #e0e0e0;
      border-radius: 8px;
      background: #fafafa;
      overflow: hidden;
    }

    .vis-header {
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

    .vis-controls {
      display: flex;
      gap: 8px;
    }

    .vis-controls button {
      padding: 6px 12px;
      border: none;
      border-radius: 4px;
      font-size: 12px;
      cursor: pointer;
      background: #e0e0e0;
      color: #333;
    }

    .vis-controls button:hover {
      background: #d0d0d0;
    }

    .vis-container {
      width: 100%;
      height: 400px;
      background: #f5f5f5;
    }

    .vis-container canvas {
      display: block;
      width: 100% !important;
      height: 100% !important;
    }

    .bb-vis-error {
      padding: 16px;
    }

    .error-message {
      color: #c62828;
    }
    """
  end
end
