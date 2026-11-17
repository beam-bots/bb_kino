# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Shared.CameraSource do
  @moduledoc """
  Camera discovery for Livebook widgets, and the endpoint arithmetic that turns
  a camera into a URL the notebook's browser can actually fetch.

  A camera is an ordinary `BB.Sensor` that also implements `BB.Camera`. This
  module only *finds* them: frames never travel through Livebook. The browser
  fetches MJPEG straight from a mounted `bb_liveview` dashboard, which is why
  everything here is about producing a correct absolute URL rather than about
  media.

  ## Optional dependency

  `bb_camera` is not a dependency of `bb_kino`. `discover/1` dispatches on a
  module resolved at runtime behind `Code.ensure_loaded?/1`, so with the
  package absent there are simply no cameras — which is the truth, since a
  robot cannot declare one without it.

      config :bb_kino, :camera, MyCameraImplementation
  """

  @default_implementation BB.Camera

  @type camera :: %{
          name: atom,
          path: [atom],
          status: :capturing | :running | :declared,
          stream: stream | nil,
          previewable?: boolean
        }

  @type stream :: %{
          format: atom | {:raw, atom},
          width: pos_integer,
          height: pos_integer,
          frame_rate: float | nil
        }

  @doc "Whether a camera implementation is installed."
  @spec available?() :: boolean
  def available? do
    Code.ensure_loaded?(implementation())
  end

  @doc """
  Every camera declared by `robot_module`, sanitised for display.

  Driver options — device paths, URLs, credentials — are not part of what a
  camera reports, and the driver's own metadata map is dropped here too.
  """
  @spec discover(module) :: [camera]
  def discover(robot_module) when is_atom(robot_module) do
    if available?() and robot?(robot_module) do
      robot_module
      |> implementation().discover()
      |> Enum.map(&describe/1)
    else
      []
    end
  end

  def discover(_robot_module), do: []

  @doc "The module implementing camera discovery."
  @spec implementation() :: module
  def implementation do
    Application.get_env(:bb_kino, :camera, @default_implementation)
  end

  @doc "A human-readable name for a camera, including where it is attached."
  @spec label(camera) :: String.t()
  def label(%{name: name, attached_to: {kind, where}}),
    do: "#{humanise(name)} (#{kind} #{humanise(where)})"

  def label(%{name: name}), do: humanise(name)

  @doc """
  The URL a notebook's browser fetches a camera preview from.

  Appends the dashboard's camera route to whatever path the endpoint already
  has, so a dashboard mounted at `/admin/arm` works as well as one at the root.
  """
  @spec stream_url(String.t(), camera) :: String.t()
  def stream_url(endpoint, camera) do
    uri = URI.parse(endpoint)
    path = Path.join([uri.path || "/", "__bb_camera__", Atom.to_string(camera.name), "mjpeg"])

    %{uri | path: path, query: nil, fragment: nil}
    |> URI.to_string()
  end

  @doc """
  Checks that an endpoint is a URL a browser could actually open.

  Deliberately refuses to guess. The Livebook runtime is frequently not the
  machine the notebook is being read on — a Nerves device, a container, a
  remote node — so `localhost` would mean the reader's own machine and quietly
  point at nothing. There is no safe default; the address has to be stated.
  """
  @spec validate_endpoint(String.t() | nil) :: {:ok, String.t()} | {:error, :missing | :relative}
  def validate_endpoint(endpoint) when endpoint in [nil, ""], do: {:error, :missing}

  def validate_endpoint(endpoint) when is_binary(endpoint) do
    case URI.parse(String.trim(endpoint)) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        {:ok, uri |> Map.put(:path, trim_path(uri.path)) |> URI.to_string()}

      _other ->
        {:error, :relative}
    end
  end

  def validate_endpoint(_endpoint), do: {:error, :relative}

  defp describe(info) do
    stream = describe_stream(info.stream_info)

    %{
      name: info.name,
      path: info.path,
      attached_to: info.attached_to,
      status: info.status,
      stream: stream,
      previewable?: match?(%{format: :jpeg}, stream)
    }
  end

  defp describe_stream(nil), do: nil

  defp describe_stream(stream_info) do
    %{
      format: stream_info.format,
      width: stream_info.width,
      height: stream_info.height,
      frame_rate: stream_info.frame_rate
    }
  end

  defp humanise(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp robot?(robot_module) do
    Code.ensure_loaded?(robot_module) and function_exported?(robot_module, :robot, 0)
  end

  defp trim_path(nil), do: nil
  defp trim_path("/"), do: nil
  defp trim_path(path), do: String.trim_trailing(path, "/")
end
