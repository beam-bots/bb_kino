# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Safety do
  @moduledoc """
  A Kino widget for displaying and controlling robot arming state.

  Shows the current safety state with colour-coded indicators:
  - Green: Armed (ready for operation)
  - Grey: Disarmed (safe state)
  - Yellow: Disarming (transitioning to safe state)
  - Red: Error (disarm failed, may not be safe)

  ## Usage

      BB.Kino.Safety.new(MyRobot)

  The widget provides:
  - Arm/Disarm toggle button
  - Force Disarm button (only in error state)
  - Real-time state updates via PubSub
  """
  use Kino.JS
  use Kino.JS.Live

  alias BB.Kino.Shared.PubSubHandler
  alias BB.Kino.Shared.RobotContext
  alias Kino.JS.Live, as: KinoLive

  @doc """
  Creates a new safety status widget for the given robot.
  """
  @spec new(module()) :: KinoLive.t()
  def new(robot_module) do
    KinoLive.new(__MODULE__, robot_module)
  end

  @impl true
  def init(robot_module, ctx) do
    case RobotContext.validate_robot(robot_module) do
      {:ok, robot} ->
        PubSubHandler.subscribe_state_machine(robot)
        safety_state = RobotContext.fetch_safety_state(robot)

        {:ok,
         assign(ctx,
           robot: robot,
           state: safety_state.state,
           in_error: safety_state.in_error
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
      payload = %{
        state: ctx.assigns.state,
        in_error: ctx.assigns.in_error
      }

      {:ok, payload, ctx}
    end
  end

  @impl true
  def handle_event("arm", _payload, ctx) do
    case BB.Safety.arm(ctx.assigns.robot) do
      :ok ->
        {:noreply, ctx}

      {:error, reason} ->
        broadcast_event(ctx, "error", %{message: "Arm failed: #{inspect(reason)}"})
        {:noreply, ctx}
    end
  end

  def handle_event("disarm", _payload, ctx) do
    case BB.Safety.disarm(ctx.assigns.robot) do
      :ok ->
        {:noreply, ctx}

      {:error, reason} ->
        broadcast_event(ctx, "error", %{message: "Disarm failed: #{inspect(reason)}"})
        {:noreply, ctx}
    end
  end

  def handle_event("force_disarm", _payload, ctx) do
    case BB.Safety.force_disarm(ctx.assigns.robot) do
      :ok ->
        {:noreply, ctx}

      {:error, reason} ->
        broadcast_event(ctx, "error", %{message: "Force disarm failed: #{inspect(reason)}"})
        {:noreply, ctx}
    end
  end

  @impl true
  def handle_info({:bb, [:state_machine], %BB.Message{payload: payload}}, ctx) do
    new_state = payload.to
    in_error = new_state == :error

    broadcast_event(ctx, "state_changed", %{
      state: new_state,
      in_error: in_error
    })

    {:noreply, assign(ctx, state: new_state, in_error: in_error)}
  end

  def handle_info(_msg, ctx) do
    {:noreply, ctx}
  end

  @impl true
  def terminate(_reason, ctx) do
    if ctx.assigns[:robot] do
      BB.unsubscribe(ctx.assigns.robot, [:state_machine])
    end

    :ok
  end

  asset "main.js" do
    """
    export function init(ctx, payload) {
      ctx.importCSS("main.css");

      if (payload.error) {
        ctx.root.innerHTML = `<div class="bb-safety bb-safety-error">
          <span class="error-message">${payload.error}</span>
        </div>`;
        return;
      }

      ctx.root.innerHTML = `
        <div class="bb-safety">
          <div class="status-row">
            <span class="status-indicator"></span>
            <span class="status-text"></span>
          </div>
          <div class="button-row">
            <button class="arm-btn">Arm</button>
            <button class="disarm-btn">Disarm</button>
            <button class="force-disarm-btn" style="display: none;">Force Disarm</button>
          </div>
          <div class="error-message" style="display: none;"></div>
        </div>
      `;

      const indicator = ctx.root.querySelector(".status-indicator");
      const statusText = ctx.root.querySelector(".status-text");
      const armBtn = ctx.root.querySelector(".arm-btn");
      const disarmBtn = ctx.root.querySelector(".disarm-btn");
      const forceDisarmBtn = ctx.root.querySelector(".force-disarm-btn");
      const errorMessage = ctx.root.querySelector(".error-message");

      function updateUI(state, inError) {
        indicator.className = "status-indicator status-" + state;
        statusText.textContent = state.charAt(0).toUpperCase() + state.slice(1);

        armBtn.disabled = state === "armed" || state === "disarming";
        disarmBtn.disabled = state === "disarmed" || state === "disarming";
        forceDisarmBtn.style.display = inError ? "inline-block" : "none";
      }

      updateUI(payload.state, payload.in_error);

      armBtn.addEventListener("click", () => {
        ctx.pushEvent("arm", {});
      });

      disarmBtn.addEventListener("click", () => {
        ctx.pushEvent("disarm", {});
      });

      forceDisarmBtn.addEventListener("click", () => {
        if (confirm("Force disarm may leave hardware in an unsafe state. Continue?")) {
          ctx.pushEvent("force_disarm", {});
        }
      });

      ctx.handleEvent("state_changed", ({ state, in_error }) => {
        updateUI(state, in_error);
        errorMessage.style.display = "none";
      });

      ctx.handleEvent("error", ({ message }) => {
        errorMessage.textContent = message;
        errorMessage.style.display = "block";
      });
    }
    """
  end

  asset "main.css" do
    """
    .bb-safety {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      padding: 16px;
      border: 1px solid #e0e0e0;
      border-radius: 8px;
      background: #fafafa;
    }

    .status-row {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 16px;
    }

    .status-indicator {
      width: 24px;
      height: 24px;
      border-radius: 50%;
      border: 2px solid rgba(0, 0, 0, 0.1);
    }

    .status-disarmed { background: #9e9e9e; }
    .status-armed { background: #4caf50; }
    .status-disarming { background: #ff9800; }
    .status-error { background: #f44336; }
    .status-idle { background: #4caf50; }
    .status-executing { background: #2196f3; }

    .status-text {
      font-size: 18px;
      font-weight: 600;
      color: #333;
    }

    .button-row {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }

    .button-row button {
      padding: 8px 16px;
      border: none;
      border-radius: 4px;
      font-size: 14px;
      cursor: pointer;
      transition: opacity 0.2s;
    }

    .button-row button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .arm-btn {
      background: #4caf50;
      color: white;
    }

    .arm-btn:hover:not(:disabled) {
      background: #43a047;
    }

    .disarm-btn {
      background: #9e9e9e;
      color: white;
    }

    .disarm-btn:hover:not(:disabled) {
      background: #757575;
    }

    .force-disarm-btn {
      background: #f44336;
      color: white;
    }

    .force-disarm-btn:hover:not(:disabled) {
      background: #d32f2f;
    }

    .error-message {
      margin-top: 12px;
      padding: 8px 12px;
      background: #ffebee;
      border: 1px solid #f44336;
      border-radius: 4px;
      color: #c62828;
      font-size: 13px;
    }
    """
  end
end
