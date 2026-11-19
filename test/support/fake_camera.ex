# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Test.FakeCamera do
  @moduledoc """
  Stands in for `bb_camera`'s discovery in tests.

  `bb_camera` is not a dependency of `bb_kino`, so there is no real
  `BB.Camera.discover/1` to call here. This answers the same shape through the
  same seam (`config :bb_kino, :camera`), which is what the widget talks to.

  It deliberately returns `options` and `metadata` fields that the real
  `BB.Camera.Info` does not have, so the widget's own sanitising can be tested:
  anything it was not explicitly asked for must not reach a notebook.
  """

  use Agent

  @doc "Starts the fake with a list of camera specifications."
  @spec start_link(keyword) :: Agent.on_start()
  def start_link(opts) do
    cameras = Keyword.fetch!(opts, :cameras)
    Agent.start_link(fn -> cameras end, name: __MODULE__)
  end

  @doc "Every camera declared by `robot_module`."
  @spec discover(module) :: [map]
  def discover(robot_module) do
    __MODULE__
    |> Agent.get(& &1)
    |> Enum.filter(&(&1.robot == robot_module))
    |> Enum.map(&info/1)
  end

  @doc "Replaces the camera list, as a robot starting or a sensor dying would."
  @spec put_cameras([map]) :: :ok
  def put_cameras(cameras) do
    Agent.update(__MODULE__, fn _previous -> cameras end)
  end

  defp info(spec) do
    name = Map.fetch!(spec, :name)

    %{
      options: [device: "/dev/video0", password: "hunter2"],
      metadata: %{serial: "SN-0001"},
      robot: spec.robot,
      name: name,
      path: Map.get(spec, :path, [:sensor, name]),
      topic: Map.get(spec, :path, [:sensor, name]),
      module: __MODULE__,
      attached_to: Map.get(spec, :attached_to, :robot),
      stream_info:
        Map.get(spec, :stream, %{format: :jpeg, width: 160, height: 120, frame_rate: 10.0}),
      status: Map.get(spec, :status, :running),
      pid: self()
    }
  end
end
