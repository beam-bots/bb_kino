# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Shared.CameraSourceTest do
  use ExUnit.Case, async: true

  alias BB.Kino.Shared.CameraSource

  @camera %{name: :eye, attached_to: {:link, :head}}

  describe "validate_endpoint/1" do
    test "accepts an absolute http or https URL" do
      assert {:ok, "http://robot.local:4000"} =
               CameraSource.validate_endpoint("http://robot.local:4000")

      assert {:ok, "https://robot.local/arm"} =
               CameraSource.validate_endpoint("https://robot.local/arm")
    end

    test "trims trailing slashes so the camera path doesn't double up" do
      assert {:ok, "http://robot.local:4000"} =
               CameraSource.validate_endpoint("http://robot.local:4000/")

      assert {:ok, "http://robot.local:4000/arm"} =
               CameraSource.validate_endpoint("http://robot.local:4000/arm/")
    end

    test "ignores surrounding whitespace, which pasted URLs collect" do
      assert {:ok, "http://robot.local:4000"} =
               CameraSource.validate_endpoint("  http://robot.local:4000  ")
    end

    test "refuses a blank endpoint rather than guessing one" do
      assert {:error, :missing} = CameraSource.validate_endpoint(nil)
      assert {:error, :missing} = CameraSource.validate_endpoint("")
    end

    test "refuses anything a browser couldn't open on its own" do
      assert {:error, :relative} = CameraSource.validate_endpoint("/robot")
      assert {:error, :relative} = CameraSource.validate_endpoint("robot.local:4000")
      assert {:error, :relative} = CameraSource.validate_endpoint("ftp://robot.local")
      assert {:error, :relative} = CameraSource.validate_endpoint(:not_a_url)
    end
  end

  describe "stream_url/2" do
    test "hangs the camera route off the dashboard's own path" do
      assert CameraSource.stream_url("http://robot.local:4000", @camera) ==
               "http://robot.local:4000/__bb_camera__/eye/mjpeg"

      assert CameraSource.stream_url("http://robot.local:4000/arm", @camera) ==
               "http://robot.local:4000/arm/__bb_camera__/eye/mjpeg"

      assert CameraSource.stream_url("https://robot.local/admin/arm", @camera) ==
               "https://robot.local/admin/arm/__bb_camera__/eye/mjpeg"
    end

    test "drops anything after the path, which can't survive the join" do
      assert CameraSource.stream_url("http://robot.local:4000/arm?tab=1#top", @camera) ==
               "http://robot.local:4000/arm/__bb_camera__/eye/mjpeg"
    end
  end

  describe "label/1" do
    test "names the camera and where it hangs" do
      assert CameraSource.label(@camera) == "Eye (link Head)"
      assert CameraSource.label(%{name: :front_camera, attached_to: :robot}) == "Front camera"
    end
  end

  describe "discover/1" do
    test "answers nothing for things that aren't robots" do
      assert CameraSource.discover(NotARobot) == []
      assert CameraSource.discover("MyRobot") == []
      assert CameraSource.discover(nil) == []
    end
  end
end
