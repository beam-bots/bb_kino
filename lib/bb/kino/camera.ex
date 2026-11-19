# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Camera do
  @moduledoc """
  A Kino widget listing a robot's cameras and previewing them.

  Cameras are discovered from the robot itself — a `BB.Sensor` that also
  implements `BB.Camera` — so there is nothing to list by hand. Discovery works
  with or without a preview endpoint, and a camera that is declared but not
  running is shown as offline rather than hidden.

  ## Frames do not come through Livebook

  No image data travels over the widget's channel. Each preview is an `<img>`
  in the notebook's browser pointing at a `bb_liveview` dashboard's MJPEG
  route, which the browser fetches directly. The widget only ever sends
  metadata: names, status, formats and a URL.

  That is why an endpoint has to be configured rather than inferred. The
  Livebook *runtime* — the machine running this code — is routinely not the
  machine the notebook is being read on: a Nerves device, a container, a remote
  node. `localhost` would mean the reader's own machine, and would quietly
  point at nothing.

  ## Usage

      BB.Kino.camera(MyRobot, endpoint: "http://robot.local:4000/robot")

  The endpoint is the base URL of a mounted dashboard — whatever path
  `bb_dashboard/2` was mounted at, as the notebook's browser would reach it.
  Leave it out and the widget lists the cameras with a field to paste one in:

      BB.Kino.camera(MyRobot)

  It can also be configured once for a whole notebook:

      config :bb_kino, :dashboard_url, "http://robot.local:4000/robot"

  ## Two things that will bite you

  * **HTTPS.** A notebook served over HTTPS cannot load an `http://` stream —
    browsers block it as mixed content, usually silently. Serve the dashboard
    over HTTPS too, or open the notebook over HTTP.
  * **Reachability.** The URL must resolve and be routable *from the browser*.
    A dashboard bound to `127.0.0.1` on a robot is not reachable from a laptop
    even when the Livebook runtime can see it.
  """
  use Kino.JS
  use Kino.JS.Live

  alias BB.Kino.Shared.CameraSource
  alias BB.Kino.Shared.PubSubHandler
  alias BB.Kino.Shared.RobotContext
  alias Kino.JS.Live, as: KinoLive

  @camera_events [
    BB.Message.Camera.BeginCapture,
    BB.Message.Camera.EndCapture
  ]

  @doc """
  Creates a camera widget for the given robot.

  ## Options

  * `:endpoint` — the base URL of a mounted `bb_liveview` dashboard, as the
    notebook's browser would reach it. Falls back to
    `config :bb_kino, :dashboard_url`, and can be set in the widget itself.
  """
  @spec new(module(), keyword()) :: KinoLive.t()
  def new(robot_module, opts \\ []) do
    KinoLive.new(__MODULE__, {robot_module, opts})
  end

  @impl true
  def init({robot_module, opts}, ctx) do
    case RobotContext.validate_robot(robot_module) do
      {:ok, robot} ->
        cameras = CameraSource.discover(robot)
        if cameras != [], do: subscribe(robot)

        endpoint =
          Keyword.get(opts, :endpoint) || Application.get_env(:bb_kino, :dashboard_url)

        {:ok, assign(ctx, robot: robot, cameras: cameras, endpoint: endpoint)}

      {:error, reason} ->
        {:ok, assign(ctx, error: reason)}
    end
  end

  @impl true
  def handle_connect(ctx) do
    if ctx.assigns[:error] do
      {:ok, %{error: ctx.assigns.error}, ctx}
    else
      {:ok, payload(ctx), ctx}
    end
  end

  @impl true
  def handle_event("set_endpoint", %{"value" => value}, ctx) do
    ctx = assign(ctx, endpoint: value)
    broadcast_event(ctx, "cameras", payload(ctx))
    {:noreply, ctx}
  end

  @impl true
  def handle_info({:bb, [:sensor | _rest], %BB.Message{payload: %module{}}}, ctx)
      when module in @camera_events do
    ctx = assign(ctx, cameras: CameraSource.discover(ctx.assigns.robot))
    broadcast_event(ctx, "cameras", payload(ctx))
    {:noreply, ctx}
  end

  def handle_info(_msg, ctx), do: {:noreply, ctx}

  @impl true
  def terminate(_reason, ctx) do
    if ctx.assigns[:robot] and ctx.assigns[:cameras] != [] do
      PubSubHandler.unsubscribe(ctx.assigns.robot, [[:sensor]])
    end

    :ok
  end

  defp describe_camera(camera, endpoint) do
    %{
      name: Atom.to_string(camera.name),
      label: CameraSource.label(camera),
      status: Atom.to_string(camera.status),
      stream: stream_text(camera.stream),
      previewable: camera.previewable? and camera.status != :declared,
      url: preview_url(camera, endpoint)
    }
  end

  defp payload(ctx) do
    {endpoint, endpoint_error} =
      case CameraSource.validate_endpoint(ctx.assigns.endpoint) do
        {:ok, endpoint} -> {endpoint, nil}
        {:error, reason} -> {nil, Atom.to_string(reason)}
      end

    %{
      error: nil,
      available: CameraSource.available?(),
      endpoint: endpoint,
      endpoint_error: endpoint_error,
      entered: ctx.assigns.endpoint || "",
      cameras: Enum.map(ctx.assigns.cameras, &describe_camera(&1, endpoint))
    }
  end

  defp preview_url(_camera, nil), do: nil

  defp preview_url(camera, endpoint) do
    if camera.previewable? and camera.status != :declared do
      CameraSource.stream_url(endpoint, camera)
    end
  end

  defp stream_text(nil), do: "Format unknown"

  defp stream_text(%{format: format, width: width, height: height, frame_rate: nil}),
    do: "#{inspect(format)} #{width}×#{height}"

  defp stream_text(%{format: format, width: width, height: height, frame_rate: rate}),
    do: "#{inspect(format)} #{width}×#{height} @ #{rate} fps"

  defp subscribe(robot) do
    PubSubHandler.subscribe(robot, [[:sensor]], message_types: @camera_events)
  end

  asset "main.js" do
    """
    export function init(ctx, payload) {
      ctx.importCSS("main.css");

      if (payload.error) {
        ctx.root.innerHTML = `<div class="bb-cameras error">${payload.error}</div>`;
        return;
      }

      const paused = new Set();

      function emptyMessage(state) {
        return state.available
          ? "This robot declares no cameras."
          : "No camera package installed — add bb_camera and a driver to see cameras here.";
      }

      function endpointNotice(state) {
        if (!state.endpoint_error) return "";

        const message = state.endpoint_error === "missing"
          ? "Enter the address of a running bb_liveview dashboard to see previews."
          : "That isn't an absolute URL. Include the scheme and host, e.g. http://robot.local:4000/robot";

        return `
          <div class="endpoint-notice">
            <p>${message}</p>
            <p class="hint">
              This has to be the address <em>your browser</em> can reach, not the
              Livebook runtime's. If the notebook is served over HTTPS, the
              dashboard must be too, or the browser will block the stream as
              mixed content.
            </p>
          </div>
        `;
      }

      function endpointField(state) {
        return `
          <div class="endpoint-field">
            <label>Dashboard URL</label>
            <input type="text" class="endpoint-input"
                   placeholder="http://robot.local:4000/robot"
                   value="${state.entered}">
          </div>
        `;
      }

      function cameraCard(camera) {
        const isPaused = paused.has(camera.name);
        const view = camera.url && !isPaused
          ? `<img class="camera-image" src="${camera.url}" alt="Live preview of ${camera.label}">`
          : `<p class="camera-placeholder">${placeholder(camera, isPaused)}</p>`;

        const toggle = camera.previewable && camera.url
          ? `<button class="camera-toggle" data-camera="${camera.name}">${isPaused ? "Resume" : "Pause"}</button>`
          : "";

        return `
          <div class="camera" data-camera="${camera.name}" data-status="${camera.status}">
            <div class="camera-header">
              <span class="camera-label">${camera.label}</span>
              <span class="camera-status ${camera.status}">${camera.status}</span>
            </div>
            <div class="camera-view">${view}</div>
            <div class="camera-footer">
              <span class="camera-stream">${camera.stream}</span>
              ${toggle}
            </div>
          </div>
        `;
      }

      function placeholder(camera, isPaused) {
        if (camera.status === "declared") return "Offline — declared in the robot but not running";
        if (!camera.previewable) return "Not previewable as MJPEG";
        if (isPaused) return "Paused";
        return "No preview endpoint configured";
      }

      function render(state) {
        const cameras = state.cameras.length
          ? `<div class="camera-grid">${state.cameras.map(cameraCard).join("")}</div>`
          : `<p class="empty">${emptyMessage(state)}</p>`;

        ctx.root.innerHTML = `
          <div class="bb-cameras">
            ${cameras}
            ${state.cameras.length ? endpointNotice(state) : ""}
            ${state.cameras.length ? endpointField(state) : ""}
          </div>
        `;

        ctx.root.querySelectorAll(".camera-toggle").forEach((button) => {
          button.addEventListener("click", () => {
            const name = button.dataset.camera;
            if (paused.has(name)) {
              paused.delete(name);
            } else {
              paused.add(name);
            }
            render(state);
          });
        });

        const input = ctx.root.querySelector(".endpoint-input");

        if (input) {
          input.addEventListener("change", (event) => {
            ctx.pushEvent("set_endpoint", { value: event.target.value });
          });

          input.addEventListener("keydown", (event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              ctx.pushEvent("set_endpoint", { value: event.target.value });
            }
          });
        }
      }

      render(payload);

      ctx.handleEvent("cameras", (state) => render(state));
    }
    """
  end

  asset "main.css" do
    """
    .bb-cameras {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      padding: 16px;
      border: 1px solid #e0e0e0;
      border-radius: 8px;
      background: #fafafa;
    }

    .bb-cameras.error {
      color: #c62828;
    }

    .camera-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 12px;
    }

    .camera {
      border: 1px solid #e0e0e0;
      border-radius: 6px;
      overflow: hidden;
      background: #fff;
    }

    .camera-header,
    .camera-footer {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      padding: 6px 10px;
    }

    .camera-footer {
      border-top: 1px solid #eee;
    }

    .camera-label {
      font-weight: 600;
      font-size: 14px;
      color: #333;
    }

    .camera-status {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.03em;
      padding: 2px 8px;
      border-radius: 999px;
      background: #eee;
      color: #666;
    }

    .camera-status.capturing {
      background: #e8f5e9;
      color: #2e7d32;
    }

    .camera-status.declared {
      background: #ffebee;
      color: #c62828;
    }

    .camera-view {
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 120px;
      background: #111;
    }

    .camera-image {
      display: block;
      width: 100%;
      height: auto;
    }

    .camera-placeholder {
      margin: 0;
      padding: 16px;
      text-align: center;
      font-size: 13px;
      color: #aaa;
    }

    .camera-stream {
      font-size: 12px;
      color: #777;
    }

    .camera-toggle {
      font-size: 12px;
      padding: 3px 10px;
      border: 1px solid #ddd;
      border-radius: 4px;
      background: #fff;
      cursor: pointer;
    }

    .empty {
      margin: 0;
      color: #777;
      font-size: 14px;
    }

    .endpoint-notice {
      margin-top: 12px;
      padding: 10px 12px;
      border-left: 3px solid #ffb300;
      background: #fff8e1;
      font-size: 13px;
      color: #5d4037;
    }

    .endpoint-notice p {
      margin: 0 0 6px 0;
    }

    .endpoint-notice .hint {
      margin: 0;
      font-size: 12px;
      color: #795548;
    }

    .endpoint-field {
      margin-top: 12px;
      display: flex;
      flex-direction: column;
      gap: 4px;
    }

    .endpoint-field label {
      font-size: 12px;
      font-weight: 600;
      color: #555;
    }

    .endpoint-input {
      padding: 6px 8px;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 13px;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }
    """
  end
end
