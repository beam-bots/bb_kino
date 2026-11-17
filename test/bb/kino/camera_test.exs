# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.CameraTest do
  use ExUnit.Case

  import Kino.Test

  alias BB.Kino.Camera
  alias BB.Kino.Shared.CameraSource
  alias BB.Kino.Test.FakeCamera
  alias BB.Kino.Test.JointRobot

  setup :configure_livebook_bridge

  setup tags do
    cameras =
      Map.get(tags, :cameras, [
        %{
          robot: JointRobot,
          name: :eye,
          path: [:sensor, :head, :eye],
          attached_to: {:link, :head}
        }
      ])

    start_supervised!(JointRobot)
    start_supervised!({FakeCamera, cameras: cameras})

    previous = Application.fetch_env(:bb_kino, :camera)
    Application.put_env(:bb_kino, :camera, FakeCamera)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:bb_kino, :camera, value)
        :error -> Application.delete_env(:bb_kino, :camera)
      end
    end)

    :ok
  end

  describe "discovery" do
    test "finds the robot's cameras without being told about them" do
      assert %{cameras: [camera]} = connect_camera()

      assert camera.name == "eye"
      assert camera.label == "Eye (link Head)"
      assert camera.status == "running"
      assert camera.stream == ":jpeg 160×120 @ 10.0 fps"
    end

    test "sends nothing about the driver's options" do
      payload = connect_camera()

      refute payload |> inspect() |> String.contains?("/dev/video0")
      refute payload |> inspect() |> String.contains?("hunter2")
      refute payload |> inspect() |> String.contains?("SN-0001")
    end

    @tag cameras: []
    test "says so when the robot has no cameras" do
      assert %{cameras: []} = connect_camera()
    end

    test "sends no image data, only metadata" do
      %{cameras: [camera]} = connect_camera(endpoint: "http://robot.local:4000/robot")

      assert Map.keys(camera) |> Enum.sort() == [
               :label,
               :name,
               :previewable,
               :status,
               :stream,
               :url
             ]
    end
  end

  describe "the endpoint" do
    test "is required rather than guessed" do
      payload = connect_camera()

      assert payload.endpoint == nil
      assert payload.endpoint_error == "missing"
      assert [%{url: nil}] = payload.cameras
    end

    test "builds a preview URL under the dashboard's mount path" do
      payload = connect_camera(endpoint: "http://robot.local:4000/robot")

      assert [%{url: "http://robot.local:4000/robot/__bb_camera__/eye/mjpeg"}] = payload.cameras
    end

    test "rejects anything that isn't absolute" do
      payload = connect_camera(endpoint: "/robot")

      assert payload.endpoint == nil
      assert payload.endpoint_error == "relative"
      assert [%{url: nil}] = payload.cameras
    end

    test "can be set from the widget" do
      kino = Camera.new(JointRobot)
      connect(kino)

      push_event(kino, "set_endpoint", %{"value" => "https://robot.local/arm"})

      assert_broadcast_event(kino, "cameras", %{cameras: cameras, endpoint: endpoint})
      assert endpoint == "https://robot.local/arm"
      assert [%{url: "https://robot.local/arm/__bb_camera__/eye/mjpeg"}] = cameras
    end

    test "falls back to the application-wide dashboard URL" do
      Application.put_env(:bb_kino, :dashboard_url, "http://robot.local:4000/robot")
      on_exit(fn -> Application.delete_env(:bb_kino, :dashboard_url) end)

      assert %{endpoint: "http://robot.local:4000/robot"} = connect_camera()
    end
  end

  describe "camera state" do
    @tag cameras: [%{robot: BB.Kino.Test.JointRobot, name: :eye, status: :declared}]
    test "an offline camera is listed, not hidden" do
      assert %{cameras: [camera]} = connect_camera(endpoint: "http://robot.local:4000/robot")

      assert camera.status == "declared"
      refute camera.previewable
      assert camera.url == nil
    end

    @tag cameras: [
           %{
             robot: BB.Kino.Test.JointRobot,
             name: :depth,
             stream: %{format: {:raw, :rgb8}, width: 64, height: 48, frame_rate: nil}
           }
         ]
    test "a camera the browser can't render gets no preview URL" do
      assert %{cameras: [camera]} = connect_camera(endpoint: "http://robot.local:4000/robot")

      refute camera.previewable
      assert camera.url == nil
      assert camera.stream == "{:raw, :rgb8} 64×48"
    end

    test "subscribes to camera lifecycle events only, not to every sensor" do
      kino = Camera.new(JointRobot)
      connect(kino)

      assert [{pid, message_types}] =
               Enum.filter(BB.PubSub.subscribers(JointRobot, [:sensor]), fn {pid, _types} ->
                 pid == kino.pid
               end)

      assert pid == kino.pid

      assert message_types == [
               BB.Message.Camera.ApplySettings,
               BB.Message.Camera.BeginCapture,
               BB.Message.Camera.EndCapture,
               BB.Message.Camera.RejectSettings
             ]
    end

    test "a camera lifecycle event refreshes the list" do
      kino = Camera.new(JointRobot, endpoint: "http://robot.local:4000/robot")
      connect(kino)

      FakeCamera.put_cameras([
        %{robot: JointRobot, name: :eye, status: :capturing},
        %{robot: JointRobot, name: :gripper_cam, status: :running}
      ])

      message = %BB.Message{
        frame_id: :eye,
        robot: JointRobot,
        payload: %BB.Message.Camera.BeginCapture{subscriber_count: 1}
      }

      send(kino.pid, {:bb, [:sensor, :head, :eye], message})

      assert_broadcast_event(kino, "cameras", %{cameras: cameras})
      assert Enum.map(cameras, & &1.name) == ["eye", "gripper_cam"]
    end
  end

  describe "with no camera package installed" do
    setup do
      Application.put_env(:bb_kino, :camera, BB.Camera)
      :ok
    end

    test "there are no cameras and the widget says why" do
      refute CameraSource.available?()

      assert %{cameras: [], available: false} = connect_camera()
    end
  end

  defp connect_camera(opts \\ []) do
    JointRobot
    |> Camera.new(opts)
    |> connect()
  end
end
