# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.ManageRobotCell do
  @moduledoc """
  A Smart Cell for managing a BB robot with all available widgets.

  Provides a unified dashboard with:
  - Safety controls (arm/disarm)
  - Joint position control
  - Event stream monitoring
  - Command execution
  - 3D visualisation

  ## Usage

  Click "+ Smart" in Livebook and select "Manage robot" to add this cell.
  Enter your robot module name and evaluate the cell.
  """
  use Kino.JS
  use Kino.JS.Live
  use Kino.SmartCell, name: "Manage robot"

  @impl true
  def init(attrs, ctx) do
    robot_module = attrs["robot_module"] || ""

    widgets = %{
      "safety" => Map.get(attrs, "safety", true),
      "joints" => Map.get(attrs, "joints", true),
      "events" => Map.get(attrs, "events", true),
      "commands" => Map.get(attrs, "commands", true),
      "visualisation" => Map.get(attrs, "visualisation", true)
    }

    {:ok, assign(ctx, robot_module: robot_module, widgets: widgets)}
  end

  @impl true
  def handle_connect(ctx) do
    payload = %{
      robot_module: ctx.assigns.robot_module,
      widgets: ctx.assigns.widgets
    }

    {:ok, payload, ctx}
  end

  @impl true
  def handle_event("update_robot_module", %{"value" => value}, ctx) do
    broadcast_event(ctx, "update_robot_module", %{"value" => value})
    {:noreply, assign(ctx, robot_module: value)}
  end

  def handle_event("toggle_widget", %{"widget" => widget, "enabled" => enabled}, ctx) do
    widgets = Map.put(ctx.assigns.widgets, widget, enabled)
    broadcast_event(ctx, "update_widgets", %{"widgets" => widgets})
    {:noreply, assign(ctx, widgets: widgets)}
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "robot_module" => ctx.assigns.robot_module,
      "safety" => ctx.assigns.widgets["safety"],
      "joints" => ctx.assigns.widgets["joints"],
      "events" => ctx.assigns.widgets["events"],
      "commands" => ctx.assigns.widgets["commands"],
      "visualisation" => ctx.assigns.widgets["visualisation"]
    }
  end

  @impl true
  def to_source(%{"robot_module" => ""}), do: ""

  def to_source(attrs) do
    robot_module = attrs["robot_module"]
    module_ast = Code.string_to_quoted!(robot_module)

    left_column = build_left_column_widgets(attrs, module_ast)
    right_column = build_right_column_widgets(attrs, module_ast)

    case {left_column, right_column} do
      {[], []} -> ""
      {left_column, right_column} -> generate_source(robot_module, left_column, right_column)
    end
  end

  defp generate_source(robot_module, left_column, right_column) do
    module_ast = Code.string_to_quoted!(robot_module)
    layout_ast = build_layout_ast(left_column, right_column)

    quote do
      robot_running? =
        try do
          BB.Process.whereis(unquote(module_ast), :registry) != nil
        rescue
          ArgumentError -> false
        end

      if robot_running? do
        unquote(layout_ast)
      else
        Kino.Markdown.new("""
        ## Robot not started

        The robot `#{unquote(robot_module)}` is not running. Start it first:

        ```elixir
        {:ok, _pid} = #{unquote(robot_module)}.start_link()
        ```

        Then re-evaluate this cell.
        """)
      end
    end
    |> Kino.SmartCell.quoted_to_string()
  end

  defp build_layout_ast([], [single]) do
    single
  end

  defp build_layout_ast([], right_column) do
    quote do: Kino.Layout.grid(unquote(right_column), columns: 1)
  end

  defp build_layout_ast(left_column, []) do
    quote do: Kino.Layout.grid(unquote(left_column), columns: 1)
  end

  defp build_layout_ast(left_column, right_column) do
    quote do
      Kino.Layout.grid(
        [
          Kino.Layout.grid(unquote(left_column), columns: 1),
          Kino.Layout.grid(unquote(right_column), columns: 1)
        ],
        columns: 2
      )
    end
  end

  defp build_left_column_widgets(attrs, module_ast) do
    []
    |> maybe_add_widget(attrs["safety"], quote(do: BB.Kino.safety(unquote(module_ast))))
    |> maybe_add_widget(attrs["joints"], quote(do: BB.Kino.joints(unquote(module_ast))))
    |> maybe_add_widget(attrs["events"], quote(do: BB.Kino.events(unquote(module_ast))))
    |> Enum.reverse()
  end

  defp build_right_column_widgets(attrs, module_ast) do
    []
    |> maybe_add_widget(
      attrs["visualisation"],
      quote(do: BB.Kino.visualisation(unquote(module_ast)))
    )
    |> maybe_add_widget(attrs["commands"], quote(do: BB.Kino.commands(unquote(module_ast))))
    |> Enum.reverse()
  end

  defp maybe_add_widget(list, true, widget), do: [widget | list]
  defp maybe_add_widget(list, _, _widget), do: list

  asset "main.js" do
    """
    export function init(ctx, payload) {
      ctx.importCSS("main.css");

      let robotModule = payload.robot_module || '';
      let isConfigured = robotModule.length > 0;
      let showSettings = !isConfigured;

      function render() {
        if (isConfigured && !showSettings) {
          // Compact connected view
          ctx.root.innerHTML = `
            <div class="manage-robot-cell compact">
              <div class="connected-header">
                <span class="connected-badge">Robot: <code>${robotModule}</code></span>
                <button class="settings-btn" title="Show settings">Settings</button>
              </div>
            </div>
          `;

          ctx.root.querySelector(".settings-btn").addEventListener("click", () => {
            showSettings = true;
            render();
          });
        } else {
          // Full configuration view
          ctx.root.innerHTML = `
            <div class="manage-robot-cell">
              ${isConfigured ? `
                <div class="connected-header">
                  <span class="connected-badge">Robot: <code>${robotModule}</code></span>
                  <button class="hide-settings-btn">Hide settings</button>
                </div>
              ` : ''}
              <div class="field">
                <label>Robot module</label>
                <div class="input-row">
                  <input type="text" class="robot-module-input" placeholder="e.g. MyRobot" value="${robotModule}">
                  <button class="connect-btn" ${robotModule ? '' : 'disabled'}>
                    ${isConfigured ? 'Update' : 'Connect'}
                  </button>
                </div>
                <span class="hint">Press <kbd>Ctrl</kbd>+<kbd>Enter</kbd> to evaluate</span>
              </div>
              <div class="widgets-section">
                <label>Widgets to display</label>
                <div class="widget-toggles">
                  <label class="toggle">
                    <input type="checkbox" data-widget="safety" ${payload.widgets.safety ? 'checked' : ''}>
                    <span>Safety</span>
                  </label>
                  <label class="toggle">
                    <input type="checkbox" data-widget="joints" ${payload.widgets.joints ? 'checked' : ''}>
                    <span>Joint Control</span>
                  </label>
                  <label class="toggle">
                    <input type="checkbox" data-widget="events" ${payload.widgets.events ? 'checked' : ''}>
                    <span>Event Stream</span>
                  </label>
                  <label class="toggle">
                    <input type="checkbox" data-widget="commands" ${payload.widgets.commands ? 'checked' : ''}>
                    <span>Commands</span>
                  </label>
                  <label class="toggle">
                    <input type="checkbox" data-widget="visualisation" ${payload.widgets.visualisation ? 'checked' : ''}>
                    <span>3D Visualisation</span>
                  </label>
                </div>
              </div>
            </div>
          `;

          const robotModuleInput = ctx.root.querySelector(".robot-module-input");
          const connectBtn = ctx.root.querySelector(".connect-btn");
          const hideSettingsBtn = ctx.root.querySelector(".hide-settings-btn");

          robotModuleInput.addEventListener("input", (e) => {
            robotModule = e.target.value;
            connectBtn.disabled = !robotModule;
          });

          robotModuleInput.addEventListener("change", (e) => {
            robotModule = e.target.value;
            ctx.pushEvent("update_robot_module", { value: robotModule });
          });

          robotModuleInput.addEventListener("keydown", (e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              robotModule = e.target.value;
              ctx.pushEvent("update_robot_module", { value: robotModule });
              if (robotModule) {
                isConfigured = true;
                showSettings = false;
                render();
              }
            }
          });

          connectBtn.addEventListener("click", () => {
            ctx.pushEvent("update_robot_module", { value: robotModule });
            if (robotModule) {
              isConfigured = true;
              showSettings = false;
              render();
            }
          });

          if (hideSettingsBtn) {
            hideSettingsBtn.addEventListener("click", () => {
              showSettings = false;
              render();
            });
          }

          ctx.root.querySelectorAll(".widget-toggles input").forEach(checkbox => {
            checkbox.addEventListener("change", (e) => {
              ctx.pushEvent("toggle_widget", {
                widget: e.target.dataset.widget,
                enabled: e.target.checked
              });
            });
          });
        }
      }

      render();

      ctx.handleEvent("update_robot_module", ({ value }) => {
        robotModule = value;
        isConfigured = value.length > 0;
        render();
      });

      ctx.handleEvent("update_widgets", ({ widgets }) => {
        payload.widgets = widgets;
        render();
      });

      ctx.handleSync(() => {
        // Ensure any pending changes are pushed before evaluation
        const input = ctx.root.querySelector(".robot-module-input");
        if (input) {
          input.dispatchEvent(new Event("change"));
        }
      });
    }
    """
  end

  asset "main.css" do
    """
    .manage-robot-cell {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      padding: 16px;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }

    .manage-robot-cell.compact {
      padding: 12px 16px;
    }

    .connected-header {
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .connected-badge {
      font-size: 14px;
      color: #333;
    }

    .connected-badge code {
      background: #e8f5e9;
      color: #2e7d32;
      padding: 2px 8px;
      border-radius: 4px;
      font-family: monospace;
      font-size: 13px;
    }

    .settings-btn,
    .hide-settings-btn {
      padding: 4px 10px;
      border: 1px solid #ddd;
      border-radius: 4px;
      background: #fff;
      font-size: 12px;
      cursor: pointer;
      color: #666;
    }

    .settings-btn:hover,
    .hide-settings-btn:hover {
      background: #f5f5f5;
      border-color: #ccc;
    }

    .manage-robot-cell .field {
      display: flex;
      flex-direction: column;
      gap: 6px;
    }

    .manage-robot-cell label {
      font-size: 13px;
      font-weight: 500;
      color: #444;
    }

    .input-row {
      display: flex;
      gap: 8px;
      align-items: center;
    }

    .manage-robot-cell .robot-module-input {
      padding: 8px 12px;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 14px;
      font-family: monospace;
      width: 100%;
      max-width: 300px;
      box-sizing: border-box;
    }

    .manage-robot-cell .robot-module-input:focus {
      outline: none;
      border-color: #3b82f6;
      box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2);
    }

    .connect-btn {
      padding: 8px 16px;
      border: none;
      border-radius: 4px;
      background: #1976d2;
      color: white;
      font-size: 14px;
      cursor: pointer;
      white-space: nowrap;
    }

    .connect-btn:hover:not(:disabled) {
      background: #1565c0;
    }

    .connect-btn:disabled {
      background: #ccc;
      cursor: not-allowed;
    }

    .hint {
      font-size: 12px;
      color: #888;
    }

    .hint kbd {
      background: #f0f0f0;
      border: 1px solid #ddd;
      border-radius: 3px;
      padding: 1px 5px;
      font-family: monospace;
      font-size: 11px;
    }

    .widgets-section {
      display: flex;
      flex-direction: column;
      gap: 8px;
    }

    .widget-toggles {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
    }

    .toggle {
      display: flex;
      align-items: center;
      gap: 6px;
      cursor: pointer;
      font-weight: normal;
    }

    .toggle input[type="checkbox"] {
      width: 16px;
      height: 16px;
      cursor: pointer;
    }

    .toggle span {
      font-size: 13px;
      color: #333;
    }
    """
  end
end
