# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Command do
  @moduledoc """
  A Kino widget for executing robot commands.

  Displays available commands in a tab view with:
  - Dynamic form for each command's arguments
  - Execute button with loading state
  - Result/error display

  ## Usage

      BB.Kino.Command.new(MyRobot)

  The widget automatically:
  - Discovers commands from the robot's DSL definition
  - Generates form inputs based on argument types
  - Executes commands via `BB.Robot.Runtime.execute/3`
  - Displays results or errors
  """
  use Kino.JS
  use Kino.JS.Live

  alias BB.Dsl.Info, as: DslInfo
  alias BB.Kino.Shared.RobotContext
  alias BB.Robot.Runtime, as: RobotRuntime
  alias Kino.JS.Live, as: KinoLive

  @doc """
  Creates a new command widget for the given robot.
  """
  @spec new(module()) :: KinoLive.t()
  def new(robot_module) do
    KinoLive.new(__MODULE__, robot_module)
  end

  @impl true
  def init(robot_module, ctx) do
    case RobotContext.validate_robot(robot_module) do
      {:ok, robot} ->
        commands = discover_commands(robot)
        state = RobotRuntime.state(robot)

        # Subscribe to state changes so we can update command availability
        BB.subscribe(robot, [:state_machine])

        {:ok,
         assign(ctx,
           robot: robot,
           commands: commands,
           state: state,
           executing: nil,
           command_pid: nil
         )}

      {:error, reason} ->
        {:ok, assign(ctx, error: reason)}
    end
  end

  defp discover_commands(robot_module) do
    robot_module
    |> DslInfo.commands()
    |> Enum.map(&format_command/1)
    |> Enum.sort_by(& &1.name)
  end

  defp format_command(cmd) do
    %{
      name: cmd.name,
      handler: cmd.handler,
      timeout: cmd.timeout,
      allowed_states: cmd.allowed_states,
      arguments: Enum.map(cmd.arguments, &format_argument/1)
    }
  end

  defp format_argument(arg) do
    case format_type(arg.type) do
      {:message, module, fields} ->
        %{
          name: arg.name,
          type: %{kind: "message", module: inspect(module), fields: fields},
          required: arg.required,
          default: arg.default,
          doc: arg.doc
        }

      type_string ->
        %{
          name: arg.name,
          type: type_string,
          required: arg.required,
          default: arg.default,
          doc: arg.doc
        }
    end
  end

  defp format_type(type) when is_atom(type) do
    if message_module?(type) do
      {:message, type, extract_schema_fields(type)}
    else
      Atom.to_string(type)
    end
  end

  defp format_type({:in, values}), do: "enum:#{inspect(values)}"
  defp format_type(type), do: inspect(type)

  defp message_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :schema, 0)
  end

  defp extract_schema_fields(module) do
    %{schema: schema_opts} = module.schema()

    schema_opts
    |> Enum.map(fn {name, opts} ->
      %{
        name: Atom.to_string(name),
        type: format_schema_type(opts[:type]),
        required: opts[:required] || false,
        doc: opts[:doc]
      }
    end)
  end

  defp format_schema_type(:float), do: "float"
  defp format_schema_type(:integer), do: "integer"
  defp format_schema_type(:boolean), do: "boolean"
  defp format_schema_type(:atom), do: "atom"
  defp format_schema_type(:string), do: "string"
  defp format_schema_type(:pos_integer), do: "integer"
  defp format_schema_type({:in, values}), do: "enum:#{inspect(values)}"
  defp format_schema_type(_), do: "text"

  @impl true
  def handle_connect(ctx) do
    if ctx.assigns[:error] do
      {:ok, %{error: ctx.assigns.error}, ctx}
    else
      payload = %{
        commands: format_commands_for_client(ctx.assigns.commands),
        state: Atom.to_string(ctx.assigns.state),
        executing: ctx.assigns.executing
      }

      {:ok, payload, ctx}
    end
  end

  defp format_commands_for_client(commands) do
    Enum.map(commands, fn cmd ->
      %{
        name: Atom.to_string(cmd.name),
        allowed_states: Enum.map(cmd.allowed_states, &Atom.to_string/1),
        arguments:
          Enum.map(cmd.arguments, fn arg ->
            %{
              name: Atom.to_string(arg.name),
              type: arg.type,
              required: arg.required,
              default: format_default(arg.default),
              doc: arg.doc
            }
          end)
      }
    end)
  end

  defp format_default(nil), do: nil
  defp format_default(value), do: inspect(value)

  @impl true
  def handle_event("execute", %{"command" => cmd_name, "args" => args}, ctx) do
    cmd_atom = String.to_existing_atom(cmd_name)

    parsed_args =
      args
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), parse_value(v)} end)
      |> Map.new()

    broadcast_event(ctx, "executing", %{command: cmd_name})

    case RobotRuntime.execute(ctx.assigns.robot, cmd_atom, parsed_args) do
      {:ok, pid} ->
        await_command(self(), pid, cmd_name)
        {:noreply, assign(ctx, executing: cmd_name, command_pid: pid)}

      {:error, reason} ->
        broadcast_event(ctx, "error", %{command: cmd_name, error: inspect(reason)})
        {:noreply, assign(ctx, executing: nil, command_pid: nil)}
    end
  end

  def handle_event("cancel", _params, ctx) do
    if pid = ctx.assigns[:command_pid], do: BB.Command.cancel(pid)
    {:noreply, ctx}
  end

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false

  defp parse_value(":" <> rest = value) when byte_size(rest) > 0 do
    String.to_existing_atom(rest)
  rescue
    ArgumentError -> value
  end

  defp parse_value("{" <> _ = value) do
    {term, _} = Code.eval_string(value)
    term
  rescue
    _ -> value
  end

  defp parse_value(%{"__module__" => module_string} = data) do
    # Handle message struct from nested form fields
    module = Module.safe_concat([module_string])

    fields =
      data
      |> Map.delete("__module__")
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), parse_value(v)} end)

    struct(module, fields)
  rescue
    _ -> data
  end

  defp parse_value(value) when is_binary(value) do
    with :error <- parse_integer(value),
         :error <- parse_float(value) do
      Module.concat([value])
    end
  end

  defp parse_value(value), do: value

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> :error
    end
  end

  defp parse_float(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> :error
    end
  end

  # Await with `:infinity` rather than polling a deadline: a continuous command
  # only returns when it stops or is cancelled, and the command's own DSL
  # `timeout` already bounds runaways. The Cancel button stops the command and
  # resolves this await.
  defp await_command(widget_pid, pid, cmd_name) do
    spawn(fn ->
      send(widget_pid, {:command_done, cmd_name, BB.Command.await(pid, :infinity)})
    end)
  end

  @impl true
  def handle_info({:command_done, cmd_name, result}, ctx) do
    case result do
      {:ok, value} ->
        broadcast_event(ctx, "result", %{command: cmd_name, result: inspect(value)})

      {:ok, value, _metadata} ->
        broadcast_event(ctx, "result", %{command: cmd_name, result: inspect(value)})

      {:error, reason} ->
        broadcast_event(ctx, "error", %{command: cmd_name, error: inspect(reason)})
    end

    {:noreply, assign(ctx, executing: nil, command_pid: nil)}
  end

  def handle_info({:bb, [:state_machine], %BB.Message{payload: payload}}, ctx) do
    broadcast_event(ctx, "state_changed", %{state: Atom.to_string(payload.to)})
    {:noreply, assign(ctx, state: payload.to)}
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
        ctx.root.innerHTML = `<div class="bb-commands bb-commands-error">
          <span class="error-message">${payload.error}</span>
        </div>`;
        return;
      }

      const commands = payload.commands || [];
      let currentState = payload.state;
      let executing = payload.executing;
      let activeTab = commands.length > 0 ? commands[0].name : null;

      ctx.root.innerHTML = `
        <div class="bb-commands">
          <div class="tab-bar"></div>
          <div class="tab-content"></div>
          <div class="result-area" style="display: none;"></div>
        </div>
      `;

      const tabBar = ctx.root.querySelector(".tab-bar");
      const tabContent = ctx.root.querySelector(".tab-content");
      const resultArea = ctx.root.querySelector(".result-area");

      function renderTabs() {
        tabBar.innerHTML = commands.map(cmd => `
          <button class="tab-btn ${cmd.name === activeTab ? 'active' : ''}" data-cmd="${cmd.name}">
            ${cmd.name}
          </button>
        `).join('');

        tabBar.querySelectorAll('.tab-btn').forEach(btn => {
          btn.addEventListener('click', () => {
            activeTab = btn.dataset.cmd;
            renderTabs();
            renderContent();
          });
        });
      }

      function renderContent() {
        const cmd = commands.find(c => c.name === activeTab);
        if (!cmd) {
          tabContent.innerHTML = '<p class="no-commands">No commands available</p>';
          return;
        }

        const canExecute = cmd.allowed_states.includes(currentState);
        const isExecuting = executing === cmd.name;

        tabContent.innerHTML = `
          <div class="command-panel">
            <div class="command-header">
              <span class="command-name">${cmd.name}</span>
              <span class="state-badge ${canExecute ? 'allowed' : 'blocked'}">
                ${canExecute ? 'Ready' : 'Requires: ' + cmd.allowed_states.join(', ')}
              </span>
            </div>
            <form class="args-form">
              ${cmd.arguments.length === 0 ? '<p class="no-args">No arguments required</p>' : ''}
              ${cmd.arguments.map(arg => `
                <div class="form-field">
                  <label>
                    ${arg.name}
                    ${arg.required ? '<span class="required">*</span>' : ''}
                  </label>
                  ${renderInput(arg)}
                  ${arg.doc ? `<span class="field-doc">${arg.doc}</span>` : ''}
                </div>
              `).join('')}
              <div class="button-row">
                <button type="submit" class="execute-btn" ${!canExecute || isExecuting ? 'disabled' : ''}>
                  ${isExecuting ? 'Running…' : 'Execute'}
                </button>
                ${isExecuting ? '<button type="button" class="cancel-btn">Cancel</button>' : ''}
              </div>
            </form>
          </div>
        `;

        const form = tabContent.querySelector('.args-form');
        form.addEventListener('submit', (e) => {
          e.preventDefault();
          if (!canExecute || isExecuting) return;

          const args = {};
          cmd.arguments.forEach(arg => {
            // Handle message types with nested fields
            if (arg.type && typeof arg.type === 'object' && arg.type.kind === 'message') {
              const messageData = { __module__: arg.type.module };
              arg.type.fields.forEach(field => {
                const input = form.querySelector(`[name="${arg.name}.${field.name}"]`);
                if (input && input.value !== '') {
                  messageData[field.name] = input.type === 'checkbox' ? input.checked : input.value;
                }
              });
              args[arg.name] = messageData;
            } else {
              const input = form.querySelector(`[name="${arg.name}"]`);
              if (input && input.value !== '') {
                args[arg.name] = input.type === 'checkbox' ? input.checked : input.value;
              }
            }
          });

          ctx.pushEvent('execute', { command: cmd.name, args: args });
        });

        const cancelBtn = tabContent.querySelector('.cancel-btn');
        if (cancelBtn) {
          cancelBtn.addEventListener('click', () => {
            ctx.pushEvent('cancel', { command: cmd.name });
          });
        }
      }

      function renderInput(arg) {
        const defaultVal = arg.default || '';

        // Handle message types with nested fields
        if (arg.type && typeof arg.type === 'object' && arg.type.kind === 'message') {
          return `
            <div class="message-fields" data-message="${arg.name}">
              ${arg.type.fields.map(field => `
                <div class="message-field">
                  <label class="field-label">${field.name}${field.required ? '<span class="required">*</span>' : ''}</label>
                  ${renderSimpleInput(field, arg.name + '.' + field.name)}
                  ${field.doc ? `<span class="field-doc">${field.doc}</span>` : ''}
                </div>
              `).join('')}
            </div>
          `;
        }

        return renderSimpleInput(arg, arg.name);
      }

      function renderSimpleInput(arg, name) {
        const defaultVal = arg.default || '';

        if (arg.type === 'boolean') {
          return `<input type="checkbox" name="${name}" ${defaultVal === 'true' ? 'checked' : ''}>`;
        }

        if (typeof arg.type === 'string' && arg.type.startsWith('enum:')) {
          const values = arg.type.replace('enum:', '').slice(1, -1).split(', ');
          return `
            <select name="${name}">
              ${values.map(v => `<option value="${v}" ${v === defaultVal ? 'selected' : ''}>${v}</option>`).join('')}
            </select>
          `;
        }

        const inputType = arg.type === 'integer' || arg.type === 'float' ? 'number' : 'text';
        const step = arg.type === 'float' ? '0.001' : '1';

        return `<input type="${inputType}" name="${name}" value="${defaultVal}" ${inputType === 'number' ? `step="${step}"` : ''}>`;
      }

      function showResult(type, message) {
        resultArea.className = `result-area ${type}`;
        resultArea.innerHTML = `<pre>${message}</pre>`;
        resultArea.style.display = 'block';
      }

      renderTabs();
      renderContent();

      ctx.handleEvent('executing', ({ command }) => {
        executing = command;
        renderContent();
        resultArea.style.display = 'none';
      });

      ctx.handleEvent('result', ({ command, result }) => {
        executing = null;
        renderContent();
        showResult('success', `Command "${command}" completed:\\n${result}`);
      });

      ctx.handleEvent('error', ({ command, error }) => {
        executing = null;
        renderContent();
        showResult('error', `Command "${command}" failed:\\n${error}`);
      });

      ctx.handleEvent('state_changed', ({ state }) => {
        currentState = state;
        renderContent();
      });
    }
    """
  end

  asset "main.css" do
    """
    .bb-commands {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      border: 1px solid #e0e0e0;
      border-radius: 8px;
      background: #fafafa;
      overflow: hidden;
    }

    .tab-bar {
      display: flex;
      background: #f5f5f5;
      border-bottom: 1px solid #e0e0e0;
      overflow-x: auto;
    }

    .tab-btn {
      padding: 12px 20px;
      border: none;
      background: transparent;
      font-size: 14px;
      cursor: pointer;
      border-bottom: 2px solid transparent;
      color: #666;
      white-space: nowrap;
    }

    .tab-btn:hover {
      background: #eee;
    }

    .tab-btn.active {
      color: #1976d2;
      border-bottom-color: #1976d2;
      font-weight: 500;
    }

    .tab-content {
      padding: 16px;
    }

    .command-panel {
      max-width: 500px;
    }

    .command-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;
    }

    .command-name {
      font-size: 18px;
      font-weight: 600;
      color: #333;
    }

    .state-badge {
      font-size: 12px;
      padding: 4px 8px;
      border-radius: 4px;
    }

    .state-badge.allowed {
      background: #e8f5e9;
      color: #2e7d32;
    }

    .state-badge.blocked {
      background: #fff3e0;
      color: #e65100;
    }

    .args-form {
      display: flex;
      flex-direction: column;
      gap: 16px;
    }

    .form-field {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }

    .form-field label {
      font-size: 13px;
      font-weight: 500;
      color: #333;
    }

    .required {
      color: #f44336;
    }

    .form-field input,
    .form-field select {
      padding: 8px 12px;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 14px;
    }

    .form-field input[type="checkbox"] {
      width: auto;
    }

    .field-doc {
      font-size: 12px;
      color: #888;
    }

    .no-args {
      color: #888;
      font-style: italic;
    }

    .message-fields {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(100px, 1fr));
      gap: 12px;
      padding: 12px;
      background: #f9f9f9;
      border: 1px solid #e0e0e0;
      border-radius: 4px;
    }

    .message-field {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }

    .message-field .field-label {
      font-size: 12px;
      font-weight: 500;
      color: #555;
    }

    .message-field input {
      padding: 6px 10px;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 13px;
    }

    .message-field .field-doc {
      font-size: 11px;
      color: #999;
    }

    .button-row {
      display: flex;
      gap: 8px;
      align-items: center;
    }

    .execute-btn {
      padding: 10px 20px;
      background: #1976d2;
      color: white;
      border: none;
      border-radius: 4px;
      font-size: 14px;
      cursor: pointer;
    }

    .execute-btn:hover:not(:disabled) {
      background: #1565c0;
    }

    .execute-btn:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .cancel-btn {
      padding: 10px 20px;
      background: #d32f2f;
      color: white;
      border: none;
      border-radius: 4px;
      font-size: 14px;
      cursor: pointer;
    }

    .cancel-btn:hover {
      background: #c62828;
    }

    .result-area {
      margin: 16px;
      padding: 12px;
      border-radius: 4px;
      font-size: 13px;
    }

    .result-area.success {
      background: #e8f5e9;
      border: 1px solid #4caf50;
    }

    .result-area.error {
      background: #ffebee;
      border: 1px solid #f44336;
    }

    .result-area pre {
      margin: 0;
      white-space: pre-wrap;
      font-family: monospace;
    }

    .no-commands {
      color: #888;
      text-align: center;
      padding: 40px;
    }

    .bb-commands-error {
      padding: 16px;
    }

    .error-message {
      color: #c62828;
    }
    """
  end
end
