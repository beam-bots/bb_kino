# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.EventStream do
  @moduledoc """
  A Kino widget for displaying a live stream of BB messages.

  Shows real-time messages from the robot's PubSub with filtering
  and pause/resume capabilities.

  ## Usage

      # Show all messages
      BB.Kino.EventStream.new(MyRobot)

      # Filter to sensor messages only
      BB.Kino.EventStream.new(MyRobot, path_filter: [:sensor])

      # Filter to specific message types
      BB.Kino.EventStream.new(MyRobot,
        path_filter: [:sensor],
        message_types: [BB.Message.Sensor.JointState]
      )

  The widget provides:
  - Real-time message display with timestamps
  - Path and message type filtering
  - Pause/Resume functionality
  - Click to expand message details
  """
  use Kino.JS
  use Kino.JS.Live

  alias BB.Kino.Shared.RobotContext
  alias Kino.JS.Live, as: KinoLive

  @default_max_messages 100

  @doc """
  Creates a new event stream widget for the given robot.

  ## Options

  - `:path_filter` - list of atoms for path filtering (default: `[]` for all)
  - `:message_types` - list of message type modules to filter by
  - `:max_messages` - maximum messages to display (default: 100)
  """
  @spec new(module(), keyword()) :: KinoLive.t()
  def new(robot_module, opts \\ []) do
    KinoLive.new(__MODULE__, {robot_module, opts})
  end

  @impl true
  def init({robot_module, opts}, ctx) do
    case RobotContext.validate_robot(robot_module) do
      {:ok, robot} ->
        path_filter = Keyword.get(opts, :path_filter, [])
        message_types = Keyword.get(opts, :message_types, [])
        max_messages = Keyword.get(opts, :max_messages, @default_max_messages)

        subscribe(robot, path_filter, message_types)

        {:ok,
         assign(ctx,
           robot: robot,
           path_filter: path_filter,
           message_types: message_types,
           max_messages: max_messages,
           paused: false,
           messages: :queue.new(),
           message_count: 0
         )}

      {:error, reason} ->
        {:ok, assign(ctx, error: reason)}
    end
  end

  defp subscribe(robot, path_filter, message_types) do
    path = if path_filter == [], do: [], else: path_filter

    if message_types == [] do
      BB.subscribe(robot, path)
    else
      BB.subscribe(robot, path, message_types: message_types)
    end
  end

  defp unsubscribe(robot, path_filter) do
    path = if path_filter == [], do: [], else: path_filter
    BB.unsubscribe(robot, path)
  end

  @impl true
  def handle_connect(ctx) do
    if ctx.assigns[:error] do
      {:ok, %{error: ctx.assigns.error}, ctx}
    else
      messages =
        ctx.assigns.messages
        |> :queue.to_list()
        |> Enum.reverse()

      payload = %{
        paused: ctx.assigns.paused,
        messages: messages,
        path_filter: Enum.join(ctx.assigns.path_filter, "."),
        max_messages: ctx.assigns.max_messages
      }

      {:ok, payload, ctx}
    end
  end

  @impl true
  def handle_event("toggle_pause", _payload, ctx) do
    new_paused = not ctx.assigns.paused
    broadcast_event(ctx, "paused_changed", %{paused: new_paused})
    {:noreply, assign(ctx, paused: new_paused)}
  end

  def handle_event("clear", _payload, ctx) do
    broadcast_event(ctx, "cleared", %{})
    {:noreply, assign(ctx, messages: :queue.new(), message_count: 0)}
  end

  def handle_event("set_filter", %{"path" => path_str}, ctx) do
    unsubscribe(ctx.assigns.robot, ctx.assigns.path_filter)

    new_path_filter =
      path_str
      |> String.split(".")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_atom/1)

    subscribe(ctx.assigns.robot, new_path_filter, ctx.assigns.message_types)
    broadcast_event(ctx, "filter_changed", %{path_filter: Enum.join(new_path_filter, ".")})

    {:noreply, assign(ctx, path_filter: new_path_filter)}
  end

  @impl true
  def handle_info({:bb, path, %BB.Message{} = message}, ctx) do
    if ctx.assigns.paused do
      {:noreply, ctx}
    else
      msg_data = format_message(path, message)
      broadcast_event(ctx, "message", msg_data)

      messages = :queue.in(msg_data, ctx.assigns.messages)
      count = ctx.assigns.message_count + 1

      messages =
        if count > ctx.assigns.max_messages do
          {_, q} = :queue.out(messages)
          q
        else
          messages
        end

      {:noreply,
       assign(ctx, messages: messages, message_count: min(count, ctx.assigns.max_messages))}
    end
  end

  def handle_info(_msg, ctx) do
    {:noreply, ctx}
  end

  defp format_message(path, message) do
    timestamp_str =
      message.wall_time
      |> DateTime.from_unix!(:nanosecond)
      |> Calendar.strftime("%H:%M:%S.%f")
      |> String.slice(0, 12)

    payload_struct = message.payload
    type_name = payload_struct.__struct__ |> Module.split() |> Enum.join(".")

    %{
      id: System.unique_integer([:positive]),
      timestamp: timestamp_str,
      path: format_path(path),
      type: type_name,
      short_type: short_type_name(payload_struct.__struct__),
      frame_id: format_frame_id(message.frame_id),
      summary: format_payload_summary(payload_struct),
      fields: format_payload_fields(payload_struct)
    }
  end

  defp format_path(path) do
    Enum.map_join(path, ".", &format_path_element/1)
  end

  defp format_path_element(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp format_path_element(ref) when is_reference(ref), do: inspect(ref)
  defp format_path_element(other), do: inspect(other)

  defp format_frame_id(nil), do: nil
  defp format_frame_id(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp format_frame_id(ref) when is_reference(ref), do: inspect(ref)
  defp format_frame_id(other), do: inspect(other)

  defp short_type_name(module) do
    module
    |> Module.split()
    |> List.last()
  end

  defp format_payload_summary(payload) do
    case payload do
      %BB.Message.Sensor.JointState{names: names} ->
        "#{length(names)} joint(s)"

      %BB.Message.Actuator.Command.Position{position: pos} ->
        format_value(pos)

      %BB.StateMachine.Transition{from: from, to: to} ->
        "#{from} → #{to}"

      _ ->
        nil
    end
  end

  defp format_payload_fields(payload) do
    payload
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {key, value} ->
      %{
        name: Atom.to_string(key),
        value: format_value(value)
      }
    end)
  end

  defp format_value([]), do: "[]"

  defp format_value(value) when is_list(value) do
    cond do
      Enum.all?(value, &is_number/1) ->
        values = Enum.map_join(value, ", ", &format_number/1)
        "[#{values}]"

      Enum.all?(value, &is_atom/1) ->
        values = Enum.map_join(value, ", ", &Atom.to_string/1)
        "[#{values}]"

      true ->
        inspect(value, limit: 10)
    end
  end

  defp format_value(value) when is_float(value), do: format_number(value)
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value, limit: 10)

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 3)
  defp format_number(n), do: Integer.to_string(n)

  @impl true
  def terminate(_reason, ctx) do
    if ctx.assigns[:robot] do
      unsubscribe(ctx.assigns.robot, ctx.assigns[:path_filter] || [])
    end

    :ok
  end

  asset "main.js" do
    """
    export function init(ctx, payload) {
      ctx.importCSS("main.css");

      if (payload.error) {
        ctx.root.innerHTML = `<div class="bb-events bb-events-error">
          <span class="error-message">${payload.error}</span>
        </div>`;
        return;
      }

      ctx.root.innerHTML = `
        <div class="bb-events">
          <div class="toolbar">
            <div class="filter-row">
              <label>Path filter:</label>
              <input type="text" class="path-filter" placeholder="e.g. sensor.joint1" value="${payload.path_filter || ''}">
              <button class="apply-filter-btn">Apply</button>
            </div>
            <div class="control-row">
              <button class="pause-btn">${payload.paused ? 'Resume' : 'Pause'}</button>
              <button class="clear-btn">Clear</button>
              <span class="message-count">0 messages</span>
            </div>
          </div>
          <div class="message-list"></div>
        </div>
      `;

      const pathFilter = ctx.root.querySelector(".path-filter");
      const applyFilterBtn = ctx.root.querySelector(".apply-filter-btn");
      const pauseBtn = ctx.root.querySelector(".pause-btn");
      const clearBtn = ctx.root.querySelector(".clear-btn");
      const messageList = ctx.root.querySelector(".message-list");
      const messageCount = ctx.root.querySelector(".message-count");

      let messages = payload.messages || [];
      let paused = payload.paused;
      const maxMessages = payload.max_messages || 100;

      function renderMessages() {
        messageList.innerHTML = messages.map(msg => renderMessage(msg)).join('');
        messageCount.textContent = `${messages.length} messages`;
      }

      function renderMessage(msg) {
        const summaryHtml = msg.summary ? `<span class="summary">${msg.summary}</span>` : '';
        const frameHtml = msg.frame_id ? `<span class="frame-id">${msg.frame_id}</span>` : '';

        const fieldsHtml = (msg.fields || []).map(f =>
          `<div class="field"><span class="field-name">${f.name}:</span> <span class="field-value">${f.value}</span></div>`
        ).join('');

        return `
          <div class="message" data-id="${msg.id}">
            <div class="message-header">
              <span class="timestamp">${msg.timestamp}</span>
              <span class="path">${msg.path}</span>
              <span class="type">${msg.short_type || msg.type}</span>
              ${summaryHtml}
              ${frameHtml}
            </div>
            <div class="message-payload" style="display: none;">
              <div class="full-type">${msg.type}</div>
              <div class="fields">${fieldsHtml}</div>
            </div>
          </div>
        `;
      }

      function addMessage(msg) {
        messages.push(msg);
        if (messages.length > maxMessages) {
          messages.shift();
        }

        const temp = document.createElement('div');
        temp.innerHTML = renderMessage(msg);
        const msgEl = temp.firstElementChild;
        messageList.appendChild(msgEl);

        if (messageList.children.length > maxMessages) {
          messageList.removeChild(messageList.firstChild);
        }

        messageCount.textContent = `${messages.length} messages`;
        messageList.scrollTop = messageList.scrollHeight;
      }

      renderMessages();

      messageList.addEventListener('click', (e) => {
        const msgEl = e.target.closest('.message');
        if (msgEl) {
          const payload = msgEl.querySelector('.message-payload');
          payload.style.display = payload.style.display === 'none' ? 'block' : 'none';
        }
      });

      pauseBtn.addEventListener('click', () => {
        ctx.pushEvent('toggle_pause', {});
      });

      clearBtn.addEventListener('click', () => {
        ctx.pushEvent('clear', {});
      });

      applyFilterBtn.addEventListener('click', () => {
        ctx.pushEvent('set_filter', { path: pathFilter.value });
      });

      pathFilter.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
          ctx.pushEvent('set_filter', { path: pathFilter.value });
        }
      });

      ctx.handleEvent('message', (msg) => {
        addMessage(msg);
      });

      ctx.handleEvent('paused_changed', ({ paused: p }) => {
        paused = p;
        pauseBtn.textContent = paused ? 'Resume' : 'Pause';
      });

      ctx.handleEvent('cleared', () => {
        messages = [];
        messageList.innerHTML = '';
        messageCount.textContent = '0 messages';
      });

      ctx.handleEvent('filter_changed', ({ path_filter }) => {
        pathFilter.value = path_filter;
      });
    }
    """
  end

  asset "main.css" do
    """
    .bb-events {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      border: 1px solid #e0e0e0;
      border-radius: 8px;
      background: #fafafa;
      overflow: hidden;
    }

    .toolbar {
      padding: 12px;
      background: #f5f5f5;
      border-bottom: 1px solid #e0e0e0;
    }

    .filter-row {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 8px;
    }

    .filter-row label {
      font-size: 13px;
      color: #666;
    }

    .path-filter {
      flex: 1;
      padding: 6px 10px;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 13px;
    }

    .control-row {
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .control-row button {
      padding: 6px 12px;
      border: none;
      border-radius: 4px;
      font-size: 13px;
      cursor: pointer;
    }

    .apply-filter-btn {
      padding: 6px 12px;
      border: none;
      border-radius: 4px;
      font-size: 13px;
      cursor: pointer;
      background: #2196f3;
      color: white;
    }

    .pause-btn {
      background: #ff9800;
      color: white;
    }

    .clear-btn {
      background: #9e9e9e;
      color: white;
    }

    .message-count {
      margin-left: auto;
      font-size: 12px;
      color: #888;
    }

    .message-list {
      max-height: 400px;
      overflow-y: auto;
    }

    .message {
      border-bottom: 1px solid #eee;
      cursor: pointer;
    }

    .message:hover {
      background: #f9f9f9;
    }

    .message-header {
      padding: 8px 12px;
      display: flex;
      gap: 12px;
      align-items: center;
      font-size: 13px;
    }

    .timestamp {
      color: #888;
      font-family: monospace;
      font-size: 12px;
    }

    .path {
      color: #2196f3;
      font-weight: 500;
    }

    .type {
      color: #666;
      font-size: 12px;
    }

    .message-payload {
      padding: 8px 12px;
      background: #f5f5f5;
      border-top: 1px solid #eee;
    }

    .summary {
      color: #4caf50;
      font-weight: 500;
      font-size: 12px;
    }

    .frame-id {
      color: #9e9e9e;
      font-size: 11px;
      font-style: italic;
    }

    .full-type {
      font-size: 11px;
      color: #666;
      margin-bottom: 8px;
      font-family: monospace;
    }

    .fields {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }

    .field {
      display: flex;
      gap: 8px;
      font-size: 13px;
    }

    .field-name {
      color: #666;
      font-weight: 500;
      min-width: 80px;
    }

    .field-value {
      font-family: monospace;
      color: #333;
      word-break: break-all;
    }

    .bb-events-error {
      padding: 16px;
    }

    .error-message {
      color: #c62828;
    }
    """
  end
end
