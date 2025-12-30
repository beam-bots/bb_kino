# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Parameters do
  @moduledoc """
  A Kino widget for viewing and editing robot parameters.

  Displays parameters in a tab-based interface with:
  - Local parameter groups as tabs
  - Remote bridge parameters in separate tabs
  - Appropriate input controls based on parameter type
  - Real-time updates via PubSub

  ## Usage

      BB.Kino.Parameters.new(MyRobot)

  The widget automatically:
  - Discovers parameters from the robot's DSL definition
  - Generates form inputs based on parameter types
  - Subscribes to parameter changes for real-time updates
  - Validates and applies parameter changes
  """
  use Kino.JS
  use Kino.JS.Live

  alias BB.Dsl.Info, as: DslInfo
  alias BB.Kino.Shared.RobotContext
  alias BB.Parameter
  alias BB.Parameter.Changed, as: ParameterChanged
  alias Kino.JS.Live, as: KinoLive

  @doc """
  Creates a new parameters widget for the given robot.
  """
  @spec new(module()) :: KinoLive.t()
  def new(robot_module) do
    KinoLive.new(__MODULE__, robot_module)
  end

  @impl true
  def init(robot_module, ctx) do
    case RobotContext.validate_robot(robot_module) do
      {:ok, robot} ->
        {tabs, parameters} = discover_local_parameters(robot)
        {bridge_tabs, bridge_params} = discover_bridge_parameters(robot)

        all_tabs = tabs ++ bridge_tabs
        all_params = Map.merge(parameters, bridge_params)

        BB.subscribe(robot, [:param])

        active_tab =
          case all_tabs do
            [first | _] -> first.id
            [] -> nil
          end

        {:ok,
         assign(ctx,
           robot: robot,
           tabs: all_tabs,
           parameters: all_params,
           active_tab: active_tab
         )}

      {:error, reason} ->
        {:ok, assign(ctx, error: reason)}
    end
  end

  defp discover_local_parameters(robot) do
    params = Parameter.list(robot)
    organise_into_tabs(params)
  end

  defp organise_into_tabs(params) do
    grouped =
      params
      |> Enum.group_by(fn {path, _meta} ->
        case path do
          [single] when is_atom(single) -> :general
          [group | _rest] -> group
        end
      end)

    tabs =
      grouped
      |> Map.keys()
      |> Enum.sort_by(fn
        :general -> {0, ""}
        name -> {1, Atom.to_string(name)}
      end)
      |> Enum.map(fn group ->
        %{
          id: group,
          label: format_tab_label(group),
          type: :local
        }
      end)

    parameters =
      grouped
      |> Enum.map(fn {group, params_list} ->
        formatted =
          params_list
          |> Enum.map(&format_local_param/1)
          |> Enum.sort_by(& &1.display_name)
          |> Map.new(fn p -> {p.path, p} end)

        {group, formatted}
      end)
      |> Map.new()

    {tabs, parameters}
  end

  defp format_tab_label(:general), do: "General"
  defp format_tab_label(name), do: name |> Atom.to_string() |> String.capitalize()

  defp format_local_param({path, meta}) do
    display_name =
      case path do
        [_single] -> Atom.to_string(hd(path))
        [_group | rest] -> Enum.map_join(rest, ".", &Atom.to_string/1)
      end

    %{
      path: path,
      display_name: display_name,
      value: meta[:value],
      type: format_type(meta[:type]),
      min: meta[:min],
      max: meta[:max],
      doc: meta[:doc]
    }
  end

  defp format_type(nil), do: "string"
  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type({:unit, unit}), do: "unit:#{unit}"
  defp format_type(other), do: inspect(other)

  defp discover_bridge_parameters(robot) do
    bridges =
      robot
      |> DslInfo.parameters()
      |> Enum.filter(&is_struct(&1, BB.Dsl.Bridge))

    tabs =
      Enum.map(bridges, fn bridge ->
        %{
          id: {:bridge, bridge.name},
          label: bridge.name |> Atom.to_string() |> String.capitalize(),
          type: :remote,
          bridge_name: bridge.name
        }
      end)

    parameters =
      bridges
      |> Enum.map(fn bridge ->
        params = fetch_remote_params(robot, bridge.name)
        {{:bridge, bridge.name}, params}
      end)
      |> Map.new()

    {tabs, parameters}
  end

  defp fetch_remote_params(robot, bridge_name) do
    case Parameter.list_remote(robot, bridge_name) do
      {:ok, params} ->
        params
        |> Enum.map(fn p ->
          id = p[:id] || p["id"]

          %{
            id: id,
            display_name: id,
            value: p[:value] || p["value"],
            type: format_type(p[:type] || p["type"]),
            min: p[:min] || p["min"],
            max: p[:max] || p["max"],
            doc: p[:doc] || p["doc"]
          }
        end)
        |> Map.new(fn p -> {p.id, p} end)

      {:error, _reason} ->
        %{__error__: "Failed to load remote parameters"}
    end
  end

  @impl true
  def handle_connect(ctx) do
    if ctx.assigns[:error] do
      {:ok, %{error: ctx.assigns.error}, ctx}
    else
      payload = %{
        tabs: format_tabs_for_client(ctx.assigns.tabs),
        parameters: format_parameters_for_client(ctx.assigns.parameters),
        activeTab: format_tab_id(ctx.assigns.active_tab)
      }

      {:ok, payload, ctx}
    end
  end

  defp format_tabs_for_client(tabs) do
    Enum.map(tabs, fn tab ->
      %{
        id: format_tab_id(tab.id),
        label: tab.label,
        type: Atom.to_string(tab.type),
        bridgeName: Map.get(tab, :bridge_name) |> maybe_to_string()
      }
    end)
  end

  defp format_tab_id(:general), do: "general"
  defp format_tab_id({:bridge, name}), do: "bridge:#{name}"
  defp format_tab_id(name) when is_atom(name), do: Atom.to_string(name)

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp format_parameters_for_client(parameters) do
    parameters
    |> Enum.map(fn {tab_id, params} ->
      {format_tab_id(tab_id), format_tab_params(params)}
    end)
    |> Map.new()
  end

  defp format_tab_params(%{__error__: error}), do: %{error: error}

  defp format_tab_params(params) when is_map(params) do
    params
    |> Enum.map(fn {key, param} ->
      {format_param_key(key), format_param_for_client(param)}
    end)
    |> Map.new()
  end

  defp format_param_key(key) when is_list(key), do: Enum.map_join(key, ".", &Atom.to_string/1)
  defp format_param_key(key), do: to_string(key)

  defp format_param_for_client(param) do
    %{
      path: format_path(param[:path] || param.id),
      displayName: param.display_name,
      value: param.value,
      type: param.type,
      min: param.min,
      max: param.max,
      doc: param.doc
    }
  end

  defp format_path(path) when is_list(path), do: Enum.map(path, &Atom.to_string/1)
  defp format_path(id), do: id

  @impl true
  def handle_event("set_parameter", %{"path" => path_strings, "value" => value}, ctx) do
    path = Enum.map(path_strings, &String.to_existing_atom/1)
    parsed_value = parse_value(value, get_param_type(ctx, path))

    case Parameter.set(ctx.assigns.robot, path, parsed_value) do
      :ok ->
        {:noreply, ctx}

      {:error, reason} ->
        broadcast_event(ctx, "error", %{
          path: path_strings,
          error: inspect(reason)
        })

        {:noreply, ctx}
    end
  end

  def handle_event(
        "set_remote_parameter",
        %{"bridge" => bridge, "id" => id, "value" => value},
        ctx
      ) do
    bridge_atom = String.to_existing_atom(bridge)
    parsed_value = parse_value(value, get_remote_param_type(ctx, bridge_atom, id))

    case Parameter.set_remote(ctx.assigns.robot, bridge_atom, id, parsed_value) do
      :ok ->
        {:noreply, ctx}

      {:error, reason} ->
        broadcast_event(ctx, "error", %{
          bridge: bridge,
          id: id,
          error: inspect(reason)
        })

        {:noreply, ctx}
    end
  end

  def handle_event("change_tab", %{"tab" => tab_id}, ctx) do
    parsed_tab = parse_tab_id(tab_id)
    {:noreply, assign(ctx, active_tab: parsed_tab)}
  end

  def handle_event("refresh_remote", %{"bridge" => bridge}, ctx) do
    bridge_atom = String.to_existing_atom(bridge)
    params = fetch_remote_params(ctx.assigns.robot, bridge_atom)
    tab_id = {:bridge, bridge_atom}

    updated_params = Map.put(ctx.assigns.parameters, tab_id, params)

    broadcast_event(ctx, "remote_refreshed", %{
      bridge: bridge,
      parameters: format_parameters_for_client(%{tab_id => params})[format_tab_id(tab_id)]
    })

    {:noreply, assign(ctx, parameters: updated_params)}
  end

  defp parse_tab_id("general"), do: :general
  defp parse_tab_id("bridge:" <> name), do: {:bridge, String.to_existing_atom(name)}
  defp parse_tab_id(name), do: String.to_existing_atom(name)

  defp get_param_type(ctx, path) do
    tab_id =
      case path do
        [single] when is_atom(single) -> :general
        [group | _] -> group
      end

    ctx.assigns.parameters
    |> Map.get(tab_id, %{})
    |> Map.get(path, %{})
    |> Map.get(:type, "string")
  end

  defp get_remote_param_type(ctx, bridge, id) do
    ctx.assigns.parameters
    |> Map.get({:bridge, bridge}, %{})
    |> Map.get(id, %{})
    |> Map.get(:type, "string")
  end

  defp parse_value(value, "boolean"), do: value == true or value == "true"

  defp parse_value(value, "integer") do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> value
    end
  end

  defp parse_value(value, "float"), do: parse_float_value(value)

  defp parse_value(value, "unit:" <> _unit), do: parse_float_value(value)

  defp parse_value(value, "atom") do
    case to_string(value) do
      ":" <> rest -> String.to_existing_atom(rest)
      rest -> String.to_existing_atom(rest)
    end
  end

  defp parse_value(value, _type), do: value

  defp parse_float_value(value) do
    case Float.parse(to_string(value)) do
      {float, _} -> float
      :error -> value
    end
  end

  @impl true
  def handle_info(
        {:bb, [:param | path], %BB.Message{payload: %ParameterChanged{} = changed}},
        ctx
      ) do
    tab_id =
      case path do
        [single] when is_atom(single) -> :general
        [group | _] -> group
      end

    updated_params =
      update_in(ctx.assigns.parameters, [tab_id, path], fn param ->
        if param, do: %{param | value: changed.new_value}, else: param
      end)

    broadcast_event(ctx, "parameter_changed", %{
      path: Enum.map(path, &Atom.to_string/1),
      value: changed.new_value
    })

    {:noreply, assign(ctx, parameters: updated_params)}
  end

  def handle_info(_msg, ctx) do
    {:noreply, ctx}
  end

  @impl true
  def terminate(_reason, ctx) do
    if ctx.assigns[:robot] do
      BB.unsubscribe(ctx.assigns.robot, [:param])
    end

    :ok
  end

  asset "main.js" do
    """
    export function init(ctx, payload) {
      ctx.importCSS("main.css");

      if (payload.error) {
        ctx.root.innerHTML = `<div class="bb-params bb-params-error">
          <span class="error-message">${payload.error}</span>
        </div>`;
        return;
      }

      const tabs = payload.tabs || [];
      let parameters = payload.parameters || {};
      let activeTab = payload.activeTab;

      if (tabs.length === 0) {
        ctx.root.innerHTML = `<div class="bb-params bb-params-empty">
          <span class="empty-message">No parameters defined</span>
        </div>`;
        return;
      }

      ctx.root.innerHTML = `
        <div class="bb-params">
          <div class="header">
            <span class="title">Parameters</span>
          </div>
          <div class="tab-bar"></div>
          <div class="tab-content"></div>
        </div>
      `;

      const tabBar = ctx.root.querySelector(".tab-bar");
      const tabContent = ctx.root.querySelector(".tab-content");

      function renderTabs() {
        tabBar.innerHTML = tabs.map(tab => `
          <button class="tab-btn ${tab.id === activeTab ? 'active' : ''} ${tab.type}" data-tab="${tab.id}">
            ${tab.label}
            ${tab.type === 'remote' ? '<span class="remote-badge">remote</span>' : ''}
          </button>
        `).join('');

        tabBar.querySelectorAll('.tab-btn').forEach(btn => {
          btn.addEventListener('click', () => {
            activeTab = btn.dataset.tab;
            ctx.pushEvent('change_tab', { tab: activeTab });
            renderTabs();
            renderContent();
          });
        });
      }

      function renderContent() {
        const tab = tabs.find(t => t.id === activeTab);
        if (!tab) {
          tabContent.innerHTML = '<p class="no-params">Select a tab</p>';
          return;
        }

        const tabParams = parameters[tab.id];

        if (tabParams && tabParams.error) {
          tabContent.innerHTML = `
            <div class="error-panel">
              <p class="error-text">${tabParams.error}</p>
              ${tab.type === 'remote' ? `<button class="refresh-btn" data-bridge="${tab.bridgeName}">Refresh</button>` : ''}
            </div>
          `;
          setupRefreshHandler();
          return;
        }

        const paramList = tabParams ? Object.values(tabParams) : [];

        if (paramList.length === 0) {
          tabContent.innerHTML = '<p class="no-params">No parameters in this group</p>';
          return;
        }

        tabContent.innerHTML = `
          <div class="param-list">
            ${paramList.map(param => renderParam(param, tab)).join('')}
          </div>
          ${tab.type === 'remote' ? `<button class="refresh-btn" data-bridge="${tab.bridgeName}">Refresh</button>` : ''}
        `;

        setupInputHandlers(tab);
        setupRefreshHandler();
      }

      function renderParam(param, tab) {
        const hasLimits = param.min !== null && param.max !== null;
        const isNumeric = param.type === 'float' || param.type === 'integer' || param.type?.startsWith('unit:');

        return `
          <div class="param-row" data-path="${Array.isArray(param.path) ? param.path.join('.') : param.path}">
            <div class="param-info">
              <span class="param-name">${param.displayName}</span>
              ${param.doc ? `<span class="param-doc">${param.doc}</span>` : ''}
            </div>
            <div class="param-input">
              ${renderInput(param, hasLimits, isNumeric, tab)}
            </div>
          </div>
        `;
      }

      function renderInput(param, hasLimits, isNumeric, tab) {
        const pathAttr = Array.isArray(param.path) ? param.path.join('.') : param.path;
        const isRemote = tab.type === 'remote';
        const bridgeAttr = isRemote ? `data-bridge="${tab.bridgeName}"` : '';

        if (param.type === 'boolean') {
          return `
            <label class="toggle">
              <input type="checkbox" ${param.value ? 'checked' : ''} data-path="${pathAttr}" ${bridgeAttr}>
              <span class="toggle-slider"></span>
            </label>
          `;
        }

        if (isNumeric && hasLimits) {
          const step = param.type === 'integer' ? 1 : (param.max - param.min) / 100;
          const unit = param.type?.startsWith('unit:') ? param.type.split(':')[1] : '';
          return `
            <div class="slider-input">
              <input type="range" min="${param.min}" max="${param.max}" step="${step}" value="${param.value || 0}" data-path="${pathAttr}" ${bridgeAttr}>
              <input type="number" min="${param.min}" max="${param.max}" step="${step}" value="${param.value || 0}" data-path="${pathAttr}" ${bridgeAttr}>
              ${unit ? `<span class="unit-label">${unit}</span>` : ''}
            </div>
          `;
        }

        if (isNumeric) {
          const step = param.type === 'integer' ? 1 : 0.01;
          const unit = param.type?.startsWith('unit:') ? param.type.split(':')[1] : '';
          return `
            <div class="number-input">
              <input type="number" step="${step}" value="${param.value || 0}" data-path="${pathAttr}" ${bridgeAttr}>
              ${unit ? `<span class="unit-label">${unit}</span>` : ''}
            </div>
          `;
        }

        if (param.type === 'atom') {
          const displayValue = param.value ? ':' + param.value : '';
          return `<input type="text" value="${displayValue}" data-path="${pathAttr}" ${bridgeAttr} class="atom-input">`;
        }

        return `<input type="text" value="${param.value || ''}" data-path="${pathAttr}" ${bridgeAttr}>`;
      }

      let debounceTimers = {};

      function setupInputHandlers(tab) {
        const isRemote = tab.type === 'remote';

        tabContent.querySelectorAll('input[type="checkbox"]').forEach(input => {
          input.addEventListener('change', (e) => {
            sendParameterChange(e.target, e.target.checked, isRemote);
          });
        });

        tabContent.querySelectorAll('.slider-input').forEach(container => {
          const slider = container.querySelector('input[type="range"]');
          const number = container.querySelector('input[type="number"]');

          slider.addEventListener('input', (e) => {
            number.value = e.target.value;
            debouncedSend(e.target, parseFloat(e.target.value), isRemote);
          });

          number.addEventListener('change', (e) => {
            slider.value = e.target.value;
            sendParameterChange(e.target, parseFloat(e.target.value), isRemote);
          });
        });

        tabContent.querySelectorAll('.number-input input').forEach(input => {
          input.addEventListener('change', (e) => {
            sendParameterChange(e.target, parseFloat(e.target.value), isRemote);
          });
        });

        tabContent.querySelectorAll('input[type="text"]').forEach(input => {
          input.addEventListener('change', (e) => {
            sendParameterChange(e.target, e.target.value, isRemote);
          });
        });
      }

      function debouncedSend(input, value, isRemote) {
        const path = input.dataset.path;
        clearTimeout(debounceTimers[path]);
        debounceTimers[path] = setTimeout(() => {
          sendParameterChange(input, value, isRemote);
        }, 100);
      }

      function sendParameterChange(input, value, isRemote) {
        const pathStr = input.dataset.path;

        if (isRemote) {
          const bridge = input.dataset.bridge;
          ctx.pushEvent('set_remote_parameter', { bridge, id: pathStr, value });
        } else {
          const path = pathStr.split('.');
          ctx.pushEvent('set_parameter', { path, value });
        }
      }

      function setupRefreshHandler() {
        tabContent.querySelectorAll('.refresh-btn').forEach(btn => {
          btn.addEventListener('click', () => {
            const bridge = btn.dataset.bridge;
            btn.disabled = true;
            btn.textContent = 'Refreshing...';
            ctx.pushEvent('refresh_remote', { bridge });
          });
        });
      }

      renderTabs();
      renderContent();

      ctx.handleEvent('parameter_changed', ({ path, value }) => {
        const pathKey = path.join('.');
        const input = tabContent.querySelector(`input[data-path="${pathKey}"]`);
        if (input) {
          if (input.type === 'checkbox') {
            input.checked = value;
          } else {
            input.value = value;
          }
        }
      });

      ctx.handleEvent('remote_refreshed', ({ bridge, parameters: newParams }) => {
        const tabId = 'bridge:' + bridge;
        parameters[tabId] = newParams;
        if (activeTab === tabId) {
          renderContent();
        }
      });

      ctx.handleEvent('error', ({ path, error }) => {
        console.error('Parameter error:', path, error);
      });
    }
    """
  end

  asset "main.css" do
    """
    .bb-params {
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

    .tab-bar {
      display: flex;
      background: #f5f5f5;
      border-bottom: 1px solid #e0e0e0;
      overflow-x: auto;
    }

    .tab-btn {
      padding: 10px 16px;
      border: none;
      background: transparent;
      font-size: 13px;
      cursor: pointer;
      border-bottom: 2px solid transparent;
      color: #666;
      white-space: nowrap;
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .tab-btn:hover {
      background: #eee;
    }

    .tab-btn.active {
      color: #1976d2;
      border-bottom-color: #1976d2;
      font-weight: 500;
    }

    .remote-badge {
      font-size: 9px;
      background: #e3f2fd;
      color: #1565c0;
      padding: 2px 5px;
      border-radius: 3px;
      text-transform: uppercase;
      font-weight: 600;
    }

    .tab-content {
      padding: 16px;
      max-height: 400px;
      overflow-y: auto;
    }

    .param-list {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }

    .param-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 8px 12px;
      background: white;
      border: 1px solid #eee;
      border-radius: 6px;
    }

    .param-row:hover {
      border-color: #ddd;
    }

    .param-info {
      display: flex;
      flex-direction: column;
      gap: 2px;
      flex: 1;
      min-width: 0;
    }

    .param-name {
      font-weight: 500;
      font-size: 13px;
      color: #333;
    }

    .param-doc {
      font-size: 11px;
      color: #888;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .param-input {
      flex-shrink: 0;
      margin-left: 16px;
    }

    .param-input input[type="text"],
    .param-input input[type="number"] {
      padding: 6px 10px;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 13px;
      width: 120px;
    }

    .param-input input[type="number"] {
      width: 80px;
    }

    .slider-input {
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .slider-input input[type="range"] {
      width: 100px;
    }

    .slider-input input[type="number"] {
      width: 70px;
    }

    .number-input {
      display: flex;
      align-items: center;
      gap: 4px;
    }

    .unit-label {
      font-size: 11px;
      color: #888;
    }

    .atom-input {
      font-family: monospace;
    }

    .toggle {
      position: relative;
      display: inline-block;
      width: 44px;
      height: 24px;
    }

    .toggle input {
      opacity: 0;
      width: 0;
      height: 0;
    }

    .toggle-slider {
      position: absolute;
      cursor: pointer;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background-color: #ccc;
      transition: 0.3s;
      border-radius: 24px;
    }

    .toggle-slider:before {
      position: absolute;
      content: "";
      height: 18px;
      width: 18px;
      left: 3px;
      bottom: 3px;
      background-color: white;
      transition: 0.3s;
      border-radius: 50%;
    }

    .toggle input:checked + .toggle-slider {
      background-color: #1976d2;
    }

    .toggle input:checked + .toggle-slider:before {
      transform: translateX(20px);
    }

    .no-params {
      color: #888;
      text-align: center;
      padding: 40px;
      font-style: italic;
    }

    .error-panel {
      text-align: center;
      padding: 20px;
    }

    .error-text {
      color: #c62828;
      margin-bottom: 12px;
    }

    .refresh-btn {
      padding: 8px 16px;
      background: #f5f5f5;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 13px;
      cursor: pointer;
      margin-top: 16px;
    }

    .refresh-btn:hover:not(:disabled) {
      background: #eee;
    }

    .refresh-btn:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .bb-params-error,
    .bb-params-empty {
      padding: 20px;
      text-align: center;
    }

    .error-message {
      color: #c62828;
    }

    .empty-message {
      color: #888;
      font-style: italic;
    }
    """
  end
end
