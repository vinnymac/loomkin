defmodule LoomkinWeb.ContextInspectorComponent do
  @moduledoc """
  Right-panel context inspector for Mission Control mode.

  Hosts existing components (FileTree, Diff, Terminal, Graph) in a tabbed
  layout with auto-follow and pin modes. Delegates all rendering to the child
  components — does not rebuild any of them.
  """

  use LoomkinWeb, :live_component

  @tabs [:files, :diff, :terminal, :graph]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, collapsed: false)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("switch_inspector_tab", %{"tab" => tab}, socket) do
    send(self(), {:inspector_tab, String.to_existing_atom(tab)})
    {:noreply, socket}
  end

  def handle_event("resume_follow", _params, socket) do
    send(self(), {:resume_follow})
    {:noreply, socket}
  end

  def handle_event("toggle_collapse", _params, socket) do
    {:noreply, assign(socket, collapsed: !socket.assigns.collapsed)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div class={panel_class(@collapsed)}>
      <%= if @collapsed do %>
        <.collapsed_strip
          tabs={@tabs}
          active_inspector_tab={@active_inspector_tab}
          myself={@myself}
        />
      <% else %>
        <%!-- Header / Tab bar --%>
        <div class="flex items-center gap-1 overflow-x-auto px-3 py-2 border-b border-gray-800 bg-gray-900/80 flex-shrink-0">
          <button
            :for={tab <- @tabs}
            phx-click="switch_inspector_tab"
            phx-value-tab={tab}
            phx-target={@myself}
            class={tab_button_class(@active_inspector_tab, tab)}
          >
            <span class="text-sm">{tab_icon(tab)}</span>
            {tab_label(tab)}
          </button>

          <div class="ml-auto flex items-center gap-2">
            <.follow_indicator
              inspector_mode={@inspector_mode}
              focused_agent={@focused_agent}
              myself={@myself}
            />
            <button
              phx-click="toggle_collapse"
              phx-target={@myself}
              class="text-gray-500 hover:text-gray-300 p-1 rounded hover:bg-gray-800/50 transition-colors"
              title="Collapse panel"
            >
              <.icon name="hero-chevron-right-mini" class="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        <%!-- Content area --%>
        <div class="flex-1 overflow-auto">
          {render_inspector_tab(@active_inspector_tab, assigns)}
        </div>
      <% end %>
    </div>
    """
  end

  # --- Collapsed strip (icon-only sidebar) ---

  defp collapsed_strip(assigns) do
    ~H"""
    <div class="flex h-full w-full items-center justify-center gap-1 px-2 py-2 xl:flex-col xl:items-center xl:justify-start xl:px-0">
      <button
        :for={tab <- @tabs}
        phx-click="switch_inspector_tab"
        phx-value-tab={tab}
        phx-target={@myself}
        class={collapsed_tab_class(@active_inspector_tab, tab)}
        title={tab_label(tab)}
      >
        <span class="text-sm">{tab_icon(tab)}</span>
      </button>

      <div class="ml-1 xl:ml-0 xl:mt-auto">
        <button
          phx-click="toggle_collapse"
          phx-target={@myself}
          class="text-gray-500 hover:text-gray-300 p-1.5 rounded hover:bg-gray-800/50 transition-colors"
          title="Expand panel"
        >
          <.icon name="hero-chevron-left-mini" class="w-3.5 h-3.5" />
        </button>
      </div>
    </div>
    """
  end

  # --- Follow mode indicator ---

  defp follow_indicator(%{focused_agent: nil} = assigns), do: ~H""

  defp follow_indicator(%{inspector_mode: :auto_follow} = assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <span class="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse"></span>
      <span class="text-xs text-green-400 truncate max-w-[120px]">Following {@focused_agent}</span>
    </div>
    """
  end

  defp follow_indicator(%{inspector_mode: :pinned} = assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <.icon name="hero-map-pin-mini" class="w-3 h-3 text-violet-400" />
      <span class="text-xs text-violet-400 truncate max-w-[120px]">Pinned to {@focused_agent}</span>
      <button
        phx-click="resume_follow"
        phx-target={@myself}
        class="text-[10px] px-1.5 py-0.5 rounded bg-violet-600/20 text-violet-400 hover:bg-violet-600/30 transition-colors"
      >
        Resume
      </button>
    </div>
    """
  end

  defp follow_indicator(assigns), do: ~H""

  # --- Tab content delegation ---

  defp render_inspector_tab(:files, assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class={if @selected_file, do: "h-1/2 overflow-auto", else: "flex-1"}>
        <.live_component
          module={LoomkinWeb.FileTreeComponent}
          id="inspector-files"
          project_path={@project_path}
          version={@file_tree_version}
          selected={@selected_file}
        />
      </div>
      <div :if={@selected_file} class="h-1/2 border-t border-gray-800 flex flex-col animate-fade-in">
        <div class="flex items-center justify-between px-3 py-2 bg-gray-900/80 border-b border-gray-800">
          <div class="flex items-center gap-2 truncate">
            <.icon name="hero-document-text-mini" class="w-3.5 h-3.5 text-violet-400 flex-shrink-0" />
            <span class="text-xs text-violet-400 font-mono truncate">{@selected_file}</span>
          </div>
        </div>
        <pre class="flex-1 overflow-auto p-3 text-xs font-mono text-gray-300 whitespace-pre">{@file_content}</pre>
      </div>
    </div>
    """
  end

  defp render_inspector_tab(:diff, assigns) do
    ~H"""
    <.live_component
      module={LoomkinWeb.DiffComponent}
      id="inspector-diff"
      diffs={@diffs}
    />
    """
  end

  defp render_inspector_tab(:terminal, assigns) do
    ~H"""
    <.live_component
      module={LoomkinWeb.TerminalComponent}
      id="inspector-terminal"
      commands={@shell_commands}
    />
    """
  end

  defp render_inspector_tab(:graph, assigns) do
    ~H"""
    <.live_component
      module={LoomkinWeb.DecisionGraphComponent}
      id="inspector-graph"
      session_id={@session_id}
      team_id={@team_id}
    />
    """
  end

  # --- Styling helpers ---

  defp panel_class(true = _collapsed),
    do:
      "w-full h-12 xl:w-10 xl:h-full flex flex-col bg-gray-900/50 border-t xl:border-t-0 xl:border-l border-gray-800 transition-all duration-200"

  defp panel_class(false = _collapsed),
    do:
      "w-full h-[18rem] xl:w-80 xl:h-full flex flex-col bg-gray-900/50 border-t xl:border-t-0 xl:border-l border-gray-800 transition-all duration-200"

  defp tab_button_class(active, tab) do
    base =
      "flex shrink-0 items-center gap-1.5 whitespace-nowrap px-3 py-1.5 text-xs font-medium rounded-lg transition-all duration-200 "

    if active == tab do
      base <> "bg-gray-800 text-violet-400"
    else
      base <> "text-gray-500 hover:text-gray-300 hover:bg-gray-800/40"
    end
  end

  defp collapsed_tab_class(active, tab) do
    base = "p-1.5 rounded-lg transition-all duration-200 "

    if active == tab do
      base <> "bg-gray-800 text-violet-400"
    else
      base <> "text-gray-500 hover:text-gray-300 hover:bg-gray-800/40"
    end
  end

  defp tab_icon(:files),
    do: raw("<span class=\"hero-folder-mini inline-block w-3.5 h-3.5\"></span>")

  defp tab_icon(:diff),
    do: raw("<span class=\"hero-code-bracket-mini inline-block w-3.5 h-3.5\"></span>")

  defp tab_icon(:terminal),
    do: raw("<span class=\"hero-command-line-mini inline-block w-3.5 h-3.5\"></span>")

  defp tab_icon(:graph),
    do: raw("<span class=\"hero-share-mini inline-block w-3.5 h-3.5\"></span>")

  defp tab_label(:files), do: "Files"
  defp tab_label(:diff), do: "Diff"
  defp tab_label(:terminal), do: "Terminal"
  defp tab_label(:graph), do: "Graph"
end
